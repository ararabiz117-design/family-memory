-- Immutable private-image attachment registration and soft deletion.
-- Objects are uploaded first to a random, never-reused path. This RPC makes
-- the object visible through the application only after metadata validation.

drop policy if exists family_storage_read on storage.objects;
create policy family_storage_read on storage.objects
for select to authenticated
using (
  bucket_id = 'family-private'
  and exists(
    select 1 from public.attachments a
    where a.storage_path = storage.objects.name
      and a.deleted_at is null
      and private.is_active_family_member(a.family_id)
  )
);

drop policy if exists family_storage_insert on storage.objects;
create policy family_storage_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'family-private'
  and name ~ '^[0-9a-f-]{36}/(people|places|events)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png)$'
  and private.is_family_writable((storage.foldername(name))[1]::uuid)
  and (
    ((storage.foldername(name))[2] = 'people' and exists(
      select 1 from public.people p
      where p.id = (storage.foldername(name))[3]::uuid
        and p.family_id = (storage.foldername(name))[1]::uuid
        and p.deleted_at is null
    ))
    or ((storage.foldername(name))[2] = 'places' and exists(
      select 1 from public.places p
      where p.id = (storage.foldername(name))[3]::uuid
        and p.family_id = (storage.foldername(name))[1]::uuid
        and p.deleted_at is null
    ))
    or ((storage.foldername(name))[2] = 'events' and exists(
      select 1 from public.events e
      where e.id = (storage.foldername(name))[3]::uuid
        and e.family_id = (storage.foldername(name))[1]::uuid
        and e.deleted_at is null
    ))
  )
);

create or replace function public.create_attachment_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  fid uuid := nullif(p_payload->>'family_id', '')::uuid;
  target_type text := p_payload->>'target_type';
  target_id uuid := nullif(p_payload->>'target_id', '')::uuid;
  object_path text := p_payload->>'storage_path';
  mime text := p_payload->>'mime_type';
  bytes integer := nullif(p_payload->>'byte_size', '')::integer;
  image_width integer := nullif(p_payload->>'width', '')::integer;
  image_height integer := nullif(p_payload->>'height', '')::integer;
  digest text := p_payload->>'sha256';
  attachment_caption text := nullif(trim(p_payload->>'caption'), '');
  attachment_id uuid;
  attachment_version integer;
  storage_metadata jsonb;
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if target_type not in ('people', 'places', 'events') or target_id is null then
    raise exception 'INVALID_ATTACHMENT_TARGET' using errcode = '22023';
  end if;
  if object_path !~ '^[0-9a-f-]{36}/(people|places|events)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png)$'
     or split_part(object_path, '/', 1)::uuid <> fid
     or split_part(object_path, '/', 2) <> target_type
     or split_part(object_path, '/', 3)::uuid <> target_id then
    raise exception 'INVALID_STORAGE_PATH' using errcode = '22023';
  end if;
  if mime not in ('image/jpeg', 'image/png')
     or bytes not between 1 and 5242880
     or image_width not between 1 and 4096
     or image_height not between 1 and 4096
     or digest !~ '^[0-9a-f]{64}$'
     or char_length(coalesce(attachment_caption, '')) > 300
     or (mime = 'image/jpeg' and object_path !~ '\.jpg$')
     or (mime = 'image/png' and object_path !~ '\.png$') then
    raise exception 'INVALID_ATTACHMENT_METADATA' using errcode = '22023';
  end if;

  select metadata into storage_metadata
    from storage.objects
    where bucket_id = 'family-private' and name = object_path;
  if not found then
    raise exception 'STORAGE_OBJECT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if nullif(storage_metadata->>'size', '') is not null
     and (storage_metadata->>'size')::bigint <> bytes then
    raise exception 'STORAGE_SIZE_MISMATCH' using errcode = '22023';
  end if;
  if nullif(storage_metadata->>'mimetype', '') is not null
     and storage_metadata->>'mimetype' <> mime then
    raise exception 'STORAGE_MIME_MISMATCH' using errcode = '22023';
  end if;

  if target_type = 'people' then
    insert into public.attachments(
      family_id, person_id, storage_path, mime_type, byte_size,
      width, height, sha256, caption
    )
    select fid, target_id, object_path, mime, bytes,
      image_width, image_height, digest, attachment_caption
    where exists(
      select 1 from public.people
      where id = target_id and family_id = fid and deleted_at is null
    )
    returning id, version into attachment_id, attachment_version;
  elsif target_type = 'places' then
    insert into public.attachments(
      family_id, place_id, storage_path, mime_type, byte_size,
      width, height, sha256, caption
    )
    select fid, target_id, object_path, mime, bytes,
      image_width, image_height, digest, attachment_caption
    where exists(
      select 1 from public.places
      where id = target_id and family_id = fid and deleted_at is null
    )
    returning id, version into attachment_id, attachment_version;
  else
    insert into public.attachments(
      family_id, event_id, storage_path, mime_type, byte_size,
      width, height, sha256, caption
    )
    select fid, target_id, object_path, mime, bytes,
      image_width, image_height, digest, attachment_caption
    where exists(
      select 1 from public.events
      where id = target_id and family_id = fid and deleted_at is null
    )
    returning id, version into attachment_id, attachment_version;
  end if;

  if attachment_id is null then
    raise exception 'ATTACHMENT_TARGET_NOT_FOUND' using errcode = 'P0001';
  end if;
  return jsonb_build_object('id', attachment_id, 'version', attachment_version);
end
$$;

create or replace function public.soft_delete_attachment_v1(
  p_family_id uuid,
  p_attachment_id uuid,
  p_expected_version integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.is_family_writable(p_family_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.attachments
    set deleted_at = now()
    where family_id = p_family_id
      and id = p_attachment_id
      and version = p_expected_version
      and deleted_at is null;
  if not found then
    raise exception 'VERSION_CONFLICT' using errcode = '40001';
  end if;
end
$$;

revoke all on function public.create_attachment_v1(jsonb) from public, anon;
revoke all on function public.soft_delete_attachment_v1(uuid, uuid, integer) from public, anon;
grant execute on function public.create_attachment_v1(jsonb) to authenticated;
grant execute on function public.soft_delete_attachment_v1(uuid, uuid, integer) to authenticated;
