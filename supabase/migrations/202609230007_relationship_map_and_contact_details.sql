-- Relationship-map UI contract. This migration is intentionally data-free.
-- Apply only to the dedicated family-memory-staging project after it resumes.

alter table public.people add column if not exists contact_address text
  check (contact_address is null or char_length(contact_address) <= 300);

-- V2 keeps the existing guarded person writer as the canonical writer, then
-- adds the optional contact fields. The returned version is the post-update
-- version so the Flutter client continues to detect concurrent edits.
create or replace function public.save_person_v2(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  fid uuid := (p_payload->>'family_id')::uuid;
  pid uuid;
  saved jsonb;
  person_version integer;
  phone_value text := nullif(trim(coalesce(p_payload->>'phone','')), '');
  email_value text := nullif(trim(coalesce(p_payload->>'email','')), '');
  address_value text := nullif(trim(coalesce(p_payload->>'contact_address','')), '');
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if char_length(coalesce(phone_value,'')) > 30
     or char_length(coalesce(email_value,'')) > 254
     or char_length(coalesce(address_value,'')) > 300 then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  saved := public.save_person_v1(p_payload);
  pid := (saved->>'id')::uuid;
  update public.people set phone=phone_value,email=email_value,contact_address=address_value
   where id=pid and family_id=fid and deleted_at is null
   returning version into person_version;
  return saved || jsonb_build_object('version',person_version);
end $$;

create or replace function public.save_person_relationship_v1(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  fid uuid := (p_payload->>'family_id')::uuid;
  rid uuid := nullif(p_payload->>'id','')::uuid;
  expected integer := nullif(p_payload->>'expected_version','')::integer;
  from_id uuid := (p_payload->>'from_person_id')::uuid;
  to_id uuid := (p_payload->>'to_person_id')::uuid;
  relation_kind public.relationship_kind := (p_payload->>'kind')::public.relationship_kind;
  relation_label text := nullif(trim(coalesce(p_payload->>'custom_label','')), '');
  relation_notes text := nullif(trim(coalesce(p_payload->>'notes','')), '');
  saved_version integer;
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if from_id is null or to_id is null or from_id=to_id
     or char_length(coalesce(relation_label,'')) > 80
     or char_length(coalesce(relation_notes,'')) > 500
     or (relation_kind='other' and relation_label is null) then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  if not exists(select 1 from public.people where id=from_id and family_id=fid and deleted_at is null)
     or not exists(select 1 from public.people where id=to_id and family_id=fid and deleted_at is null) then
    raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
  end if;
  if rid is null then
    insert into public.person_relationships(family_id,from_person_id,to_person_id,kind,custom_label,notes)
    values(fid,from_id,to_id,relation_kind,relation_label,relation_notes)
    returning id,version into rid,saved_version;
  else
    if expected is null then raise exception 'EXPECTED_VERSION_REQUIRED' using errcode='22023'; end if;
    update public.person_relationships set from_person_id=from_id,to_person_id=to_id,
      kind=relation_kind,custom_label=relation_label,notes=relation_notes
    where id=rid and family_id=fid and version=expected and deleted_at is null
    returning version into saved_version;
    if not found then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
  end if;
  return jsonb_build_object('id',rid,'version',saved_version);
end $$;

revoke all on function public.save_person_v2(jsonb),public.save_person_relationship_v1(jsonb) from public,anon;
grant execute on function public.save_person_v2(jsonb),public.save_person_relationship_v1(jsonb) to authenticated;
