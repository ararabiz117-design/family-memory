-- Atomic Flutter write contract. Apply only after the initial schema.

create or replace function public.save_person_v1(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  fid uuid := (p_payload->>'family_id')::uuid;
  pid uuid := nullif(p_payload->>'id','')::uuid;
  focus_id uuid := nullif(p_payload->>'focus_person_id','')::uuid;
  expected integer := nullif(p_payload->>'expected_version','')::integer;
  deceased_expected integer := nullif(p_payload->>'deceased_expected_version','')::integer;
  person_version integer;
  deceased_version integer;
  life public.life_status := coalesce(nullif(p_payload->>'life_status',''),'unknown')::public.life_status;
  person_kind_value public.person_kind := coalesce(nullif(p_payload->>'kind',''),'family_relative')::public.person_kind;
  birth_value date := nullif(p_payload->>'birth_date','')::date;
  birth_precision_value public.date_precision := coalesce(nullif(p_payload->>'birth_precision',''),'unknown')::public.date_precision;
  death_value date := nullif(p_payload->>'death_date','')::date;
  death_precision_value public.date_precision := coalesce(nullif(p_payload->>'death_precision',''),'unknown')::public.date_precision;
  relation_label text := nullif(trim(p_payload->>'relationship_label'),'');
  existing_deceased public.deceased_profiles%rowtype;
  existing_relation public.person_relationships%rowtype;
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if char_length(trim(coalesce(p_payload->>'display_name',''))) not between 1 and 120 then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  if (birth_precision_value='unknown') <> (birth_value is null)
     or (death_precision_value='unknown') <> (death_value is null) then
    raise exception 'INVALID_DATE_PRECISION' using errcode='22023';
  end if;

  if pid is null then
    insert into public.people(
      family_id,display_name,name_kana,kind,show_in_tree,life_status,
      birth_date,birth_date_precision,death_date,death_date_precision,
      nicknames,how_to_recognize,contact_note,notes,living_person_consent_confirmed
    ) values(
      fid,trim(p_payload->>'display_name'),nullif(trim(p_payload->>'name_kana'),''),person_kind_value,
      person_kind_value='family_relative',life,birth_value,birth_precision_value,death_value,death_precision_value,
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'nicknames','[]'::jsonb))),'{}'::text[]),
      nullif(trim(p_payload->>'how_to_address'),''),nullif(trim(p_payload->>'last_met'),''),
      nullif(trim(p_payload->>'notes'),''),coalesce((p_payload->>'living_person_consent_confirmed')::boolean,false)
    ) returning id,version into pid,person_version;
  else
    if expected is null then raise exception 'EXPECTED_VERSION_REQUIRED' using errcode='22023'; end if;
    update public.people set
      display_name=trim(p_payload->>'display_name'), name_kana=nullif(trim(p_payload->>'name_kana'),''),
      kind=person_kind_value, show_in_tree=person_kind_value='family_relative', life_status=life,
      birth_date=birth_value,birth_date_precision=birth_precision_value,
      death_date=death_value,death_date_precision=death_precision_value,
      nicknames=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'nicknames','[]'::jsonb))),'{}'::text[]),
      how_to_recognize=nullif(trim(p_payload->>'how_to_address'),''),contact_note=nullif(trim(p_payload->>'last_met'),''),
      notes=nullif(trim(p_payload->>'notes'),''),
      living_person_consent_confirmed=coalesce((p_payload->>'living_person_consent_confirmed')::boolean,false)
    where id=pid and family_id=fid and version=expected and deleted_at is null
    returning version into person_version;
    if not found then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
  end if;

  select * into existing_deceased from public.deceased_profiles
    where family_id=fid and person_id=pid and deleted_at is null for update;
  if life='deceased' then
    if found then
      if deceased_expected is null or existing_deceased.version<>deceased_expected then
        raise exception 'VERSION_CONFLICT' using errcode='40001';
      end if;
      update public.deceased_profiles set
        posthumous_name=nullif(trim(p_payload->>'posthumous_name'),''),
        religious_form=nullif(trim(p_payload->>'religious_form'),''),
        denomination=nullif(trim(p_payload->>'denomination'),''),
        notes=nullif(trim(p_payload->>'religion_note'),'')
      where id=existing_deceased.id returning version into deceased_version;
    else
      insert into public.deceased_profiles(family_id,person_id,posthumous_name,religious_form,denomination,notes)
      values(fid,pid,nullif(trim(p_payload->>'posthumous_name'),''),nullif(trim(p_payload->>'religious_form'),''),
        nullif(trim(p_payload->>'denomination'),''),nullif(trim(p_payload->>'religion_note'),''))
      returning version into deceased_version;
    end if;
  elsif found then
    if deceased_expected is null or existing_deceased.version<>deceased_expected then
      raise exception 'VERSION_CONFLICT' using errcode='40001';
    end if;
    update public.deceased_profiles set deleted_at=now() where id=existing_deceased.id;
    deceased_version:=null;
  end if;

  if focus_id is not null and focus_id<>pid and relation_label is not null then
    if not exists(select 1 from public.people where id=focus_id and family_id=fid and deleted_at is null) then
      raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
    end if;
    select * into existing_relation from public.person_relationships
      where family_id=fid and from_person_id=focus_id and to_person_id=pid and kind='relative_unknown' and deleted_at is null
      for update;
    if found then
      update public.person_relationships set custom_label=relation_label where id=existing_relation.id;
    else
      insert into public.person_relationships(family_id,from_person_id,to_person_id,kind,custom_label)
      values(fid,focus_id,pid,'relative_unknown',relation_label);
    end if;
  end if;

  return jsonb_build_object('id',pid,'version',person_version,'deceased_version',deceased_version);
end $$;

create or replace function public.save_event_v1(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  fid uuid := (p_payload->>'family_id')::uuid;
  eid uuid := nullif(p_payload->>'id','')::uuid;
  expected integer := nullif(p_payload->>'expected_version','')::integer;
  subject_id uuid := (p_payload->>'subject_person_id')::uuid;
  place_value uuid := nullif(p_payload->>'place_id','')::uuid;
  event_date_value date := nullif(p_payload->>'event_date','')::date;
  event_version integer;
  item jsonb;
  offset_days integer;
begin
  if auth.uid() is null or not private.is_family_writable(fid) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if char_length(trim(coalesce(p_payload->>'title',''))) not between 1 and 160
     or not exists(select 1 from public.people where id=subject_id and family_id=fid and deleted_at is null)
     or (place_value is not null and not exists(select 1 from public.places where id=place_value and family_id=fid and deleted_at is null)) then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;

  if eid is null then
    insert into public.events(
      family_id,kind,title,status,is_candidate,event_date,event_date_precision,place_id,
      officiant_or_host,summary,lessons
    ) values(
      fid,coalesce(nullif(p_payload->>'kind',''),'other')::public.event_kind,trim(p_payload->>'title'),
      coalesce(nullif(p_payload->>'status',''),'planned')::public.event_status,
      coalesce((p_payload->>'is_candidate')::boolean,false),event_date_value,
      case when event_date_value is null then 'unknown' else 'day' end::public.date_precision,
      place_value,nullif(trim(p_payload->>'officiant_or_host'),''),nullif(trim(p_payload->>'summary'),''),
      nullif(trim(p_payload->>'lessons'),'')
    ) returning id,version into eid,event_version;
  else
    if expected is null then raise exception 'EXPECTED_VERSION_REQUIRED' using errcode='22023'; end if;
    update public.events set
      kind=coalesce(nullif(p_payload->>'kind',''),'other')::public.event_kind,title=trim(p_payload->>'title'),
      status=coalesce(nullif(p_payload->>'status',''),'planned')::public.event_status,
      is_candidate=coalesce((p_payload->>'is_candidate')::boolean,false),event_date=event_date_value,
      event_date_precision=case when event_date_value is null then 'unknown' else 'day' end::public.date_precision,
      place_id=place_value,officiant_or_host=nullif(trim(p_payload->>'officiant_or_host'),''),
      summary=nullif(trim(p_payload->>'summary'),''),lessons=nullif(trim(p_payload->>'lessons'),'')
    where id=eid and family_id=fid and version=expected and deleted_at is null returning version into event_version;
    if not found then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
  end if;

  update public.event_people set deleted_at=now() where family_id=fid and event_id=eid and deleted_at is null;
  insert into public.event_people(family_id,event_id,person_id,role_label) values(fid,eid,subject_id,'対象者');

  update public.event_attendees set deleted_at=now() where family_id=fid and event_id=eid and deleted_at is null;
  for item in select value from jsonb_array_elements(coalesce(p_payload->'attendees','[]'::jsonb)) loop
    insert into public.event_attendees(family_id,event_id,person_id,display_name_snapshot,relationship_snapshot,status)
    values(fid,eid,nullif(item->>'person_id','')::uuid,trim(item->>'display_name'),nullif(trim(item->>'relationship'),''),
      coalesce(nullif(item->>'status',''),'unanswered')::public.attendance_status);
  end loop;

  update public.event_expenses set deleted_at=now() where family_id=fid and event_id=eid and deleted_at is null;
  for item in select value from jsonb_array_elements(coalesce(p_payload->'expenses','[]'::jsonb)) loop
    insert into public.event_expenses(family_id,event_id,kind,amount_yen,recipient_label)
    values(fid,eid,coalesce(nullif(item->>'kind',''),'other')::public.expense_kind,
      nullif(item->>'amount_yen','')::bigint,nullif(trim(item->>'payer'),''));
  end loop;

  update public.reminders set deleted_at=now() where family_id=fid and event_id=eid and deleted_at is null;
  if event_date_value is not null and not coalesce((p_payload->>'is_candidate')::boolean,false) then
    for offset_days in select value::integer from jsonb_array_elements_text(coalesce(p_payload->'notification_days','[]'::jsonb)) loop
      if offset_days between 0 and 3650 then
        insert into public.reminders(family_id,event_id,title,due_date,notify_offset_days)
        values(fid,eid,'予定の確認',event_date_value,offset_days);
      end if;
    end loop;
  end if;
  return jsonb_build_object('id',eid,'version',event_version);
end $$;

create or replace function public.soft_delete_event_v1(p_family_id uuid,p_event_id uuid,p_expected_version integer) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.is_family_writable(p_family_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  update public.event_people set deleted_at=now() where family_id=p_family_id and event_id=p_event_id and deleted_at is null;
  update public.event_attendees set deleted_at=now() where family_id=p_family_id and event_id=p_event_id and deleted_at is null;
  update public.event_expenses set deleted_at=now() where family_id=p_family_id and event_id=p_event_id and deleted_at is null;
  update public.reminders set deleted_at=now() where family_id=p_family_id and event_id=p_event_id and deleted_at is null;
  update public.events set deleted_at=now()
    where family_id=p_family_id and id=p_event_id and version=p_expected_version and deleted_at is null;
  if not found then raise exception 'VERSION_CONFLICT' using errcode='40001'; end if;
end $$;

revoke all on function public.save_person_v1(jsonb),public.save_event_v1(jsonb),public.soft_delete_event_v1(uuid,uuid,integer) from public,anon;
grant execute on function public.save_person_v1(jsonb),public.save_event_v1(jsonb),public.soft_delete_event_v1(uuid,uuid,integer) to authenticated;
