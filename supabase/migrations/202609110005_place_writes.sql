-- Version-checked place editing and optional deceased/person association.

alter table public.places
  add column if not exists landmark text check (char_length(landmark) <= 500),
  add column if not exists directions text check (char_length(directions) <= 2000);

create or replace function public.save_place_v1(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  fid uuid := (p_payload->>'family_id')::uuid;
  saved_place_id uuid := nullif(p_payload->>'id','')::uuid;
  expected integer := nullif(p_payload->>'expected_version','')::integer;
  place_kind_value public.place_kind := coalesce(
    nullif(p_payload->>'kind',''),'other'
  )::public.place_kind;
  related_person_id uuid := nullif(p_payload->>'related_person_id','')::uuid;
  relation_kind public.person_place_kind := coalesce(
    nullif(p_payload->>'person_place_kind',''),'other'
  )::public.person_place_kind;
  saved_version integer;
  existing_link public.person_places%rowtype;
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if char_length(trim(coalesce(p_payload->>'name',''))) not between 1 and 160
     or char_length(coalesce(p_payload->>'address','')) > 300
     or char_length(coalesce(p_payload->>'block_plot','')) > 200
     or char_length(coalesce(p_payload->>'landmark','')) > 500
     or char_length(coalesce(p_payload->>'directions','')) > 2000 then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  if nullif(trim(p_payload->>'external_map_url'),'') is not null
     and trim(p_payload->>'external_map_url') !~ '^https://' then
    raise exception 'MAP_URL_MUST_USE_HTTPS' using errcode='22023';
  end if;

  if saved_place_id is null then
    insert into public.places(
      family_id,kind,name,address,block_plot,landmark,directions,
      external_map_url,notes
    ) values(
      fid,place_kind_value,trim(p_payload->>'name'),
      nullif(trim(p_payload->>'address'),''),
      nullif(trim(p_payload->>'block_plot'),''),
      nullif(trim(p_payload->>'landmark'),''),
      nullif(trim(p_payload->>'directions'),''),
      nullif(trim(p_payload->>'external_map_url'),''),
      nullif(trim(p_payload->>'notes'),'')
    ) returning id,version into saved_place_id,saved_version;
  else
    if expected is null then
      raise exception 'EXPECTED_VERSION_REQUIRED' using errcode='22023';
    end if;
    update public.places set
      kind=place_kind_value,
      name=trim(p_payload->>'name'),
      address=nullif(trim(p_payload->>'address'),''),
      block_plot=nullif(trim(p_payload->>'block_plot'),''),
      landmark=nullif(trim(p_payload->>'landmark'),''),
      directions=nullif(trim(p_payload->>'directions'),''),
      external_map_url=nullif(trim(p_payload->>'external_map_url'),''),
      notes=nullif(trim(p_payload->>'notes'),'')
    where id=saved_place_id and family_id=fid and version=expected
      and deleted_at is null
    returning version into saved_version;
    if not found then
      raise exception 'VERSION_CONFLICT' using errcode='40001';
    end if;
  end if;

  if related_person_id is not null then
    if not exists(
      select 1 from public.people
      where id=related_person_id and family_id=fid and deleted_at is null
    ) then
      raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
    end if;
    select * into existing_link from public.person_places
    where family_id=fid and person_id=related_person_id
      and person_places.place_id=saved_place_id
      and kind=relation_kind and deleted_at is null
    for update;
    if not found then
      insert into public.person_places(family_id,person_id,place_id,kind)
      values(fid,related_person_id,saved_place_id,relation_kind);
    end if;
  end if;

  return jsonb_build_object('id',saved_place_id,'version',saved_version);
end $$;

revoke all on function public.save_place_v1(jsonb) from public,anon;
grant execute on function public.save_place_v1(jsonb) to authenticated;
