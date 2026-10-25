-- Avoid evaluating record fields that do not exist for the current trigger table.
-- This only repairs the family-memory schema trigger; it changes no user data.
create or replace function private.check_same_family_refs() returns trigger
language plpgsql set search_path='' as $$
declare f uuid;
begin
  if tg_table_name='deceased_profiles' then
    select family_id into f from public.people where id=new.person_id;
  elsif tg_table_name='person_places' then
    if not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id)
       or not exists(select 1 from public.places where id=new.place_id and family_id=new.family_id) then
      raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
    end if;
    return new;
  elsif tg_table_name='event_people' then
    if not exists(select 1 from public.events where id=new.event_id and family_id=new.family_id)
       or not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id) then
      raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
    end if;
    return new;
  elsif tg_table_name='event_attendees' then
    if not exists(select 1 from public.events where id=new.event_id and family_id=new.family_id)
       or (new.person_id is not null and not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id)) then
      raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
    end if;
    return new;
  elsif tg_table_name='event_expenses' then
    select family_id into f from public.events where id=new.event_id;
  elsif tg_table_name='events' then
    if new.place_id is null then return new; end if;
    select family_id into f from public.places where id=new.place_id;
  elsif tg_table_name='gift_records' then
    if new.person_id is null then return new; end if;
    select family_id into f from public.people where id=new.person_id;
  elsif tg_table_name='reminders' then
    if new.event_id is null then return new; end if;
    select family_id into f from public.events where id=new.event_id;
  elsif tg_table_name='attachments' then
    if new.person_id is not null then
      select family_id into f from public.people where id=new.person_id;
    elsif new.place_id is not null then
      select family_id into f from public.places where id=new.place_id;
    else
      select family_id into f from public.events where id=new.event_id;
    end if;
  else
    return new;
  end if;

  if f is distinct from new.family_id then
    raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514';
  end if;
  if tg_table_name='attachments' then
    if split_part(new.storage_path,'/',1)::uuid <> new.family_id then
      raise exception 'CROSS_FAMILY_STORAGE_PATH' using errcode='23514';
    end if;
    if new.person_id is not null and (split_part(new.storage_path,'/',2)<>'people' or split_part(new.storage_path,'/',3)::uuid<>new.person_id) then
      raise exception 'INVALID_STORAGE_PATH' using errcode='23514';
    end if;
    if new.place_id is not null and (split_part(new.storage_path,'/',2)<>'places' or split_part(new.storage_path,'/',3)::uuid<>new.place_id) then
      raise exception 'INVALID_STORAGE_PATH' using errcode='23514';
    end if;
    if new.event_id is not null and (split_part(new.storage_path,'/',2)<>'events' or split_part(new.storage_path,'/',3)::uuid<>new.event_id) then
      raise exception 'INVALID_STORAGE_PATH' using errcode='23514';
    end if;
  end if;
  if tg_table_name='deceased_profiles' and not exists(select 1 from public.people where id=new.person_id and life_status='deceased') then
    raise exception 'PERSON_NOT_DECEASED' using errcode='23514';
  end if;
  return new;
end $$;
