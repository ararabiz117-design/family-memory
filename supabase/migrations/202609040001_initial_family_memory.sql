-- Family Memory MVP schema. Apply to a fresh Supabase project.
-- No real people or credentials belong in this migration.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon;

create type public.family_role as enum ('owner', 'editor', 'viewer');
create type public.member_status as enum ('pending', 'active', 'suspended');
create type public.invite_status as enum ('active', 'accepted', 'approved', 'revoked', 'expired');
create type public.person_kind as enum ('family_relative', 'related_person', 'temple_business_contact');
create type public.life_status as enum ('living', 'deceased', 'unknown');
create type public.date_precision as enum ('unknown', 'year', 'month', 'day');
create type public.gender_value as enum ('male', 'female', 'other', 'unknown');
create type public.relationship_kind as enum ('parent_child', 'adopted_parent_child', 'step_parent_child', 'spouse', 'partner', 'sibling', 'relative_unknown', 'acquaintance', 'work_related', 'temple_related', 'other');
create type public.place_kind as enum ('cemetery', 'grave_site', 'temple', 'ossuary', 'funeral_hall', 'memorial_venue', 'home', 'hospital_care_facility', 'restaurant', 'remains_storage', 'altar_memorial_storage', 'other');
create type public.person_place_kind as enum ('death_place', 'cemetery', 'grave', 'temple', 'ossuary', 'remains', 'altar_memorial_tablet', 'funeral_venue', 'memorial_venue', 'other');
create type public.event_kind as enum ('funeral', 'wake', 'cremation', 'interment', 'forty_ninth_day', 'memorial_service', 'first_bon', 'obon', 'equinox', 'grave_visit', 'chugen', 'seibo', 'return_gift', 'other');
create type public.event_status as enum ('planned', 'preparing', 'completed', 'cancelled');
create type public.attendance_status as enum ('invited', 'attending', 'attended', 'absent', 'unanswered');
create type public.expense_kind as enum ('offering', 'priest_transport', 'meal', 'return_gift', 'venue', 'flowers', 'transport', 'lodging', 'other');
create type public.gift_kind as enum ('chugen', 'seibo', 'condolence', 'return_gift', 'obon', 'other');
create type public.gift_direction as enum ('given', 'received');
create type public.job_status as enum ('queued', 'processing', 'completed', 'failed', 'cancelled');
create type public.deletion_scope as enum ('record', 'account', 'family');

create or replace function private.exists_in_array_over_length(input_values text[], max_len integer) returns boolean
language sql immutable set search_path = '' as $$ select exists(select 1 from unnest(input_values) v where char_length(v) > max_len) $$;
create or replace function public.exists_in_array_over_length(input_values text[], max_len integer) returns boolean
language sql immutable set search_path = '' as $$ select private.exists_in_array_over_length(input_values,max_len) $$;
revoke all on function public.exists_in_array_over_length(text[],integer) from public, anon;
grant execute on function public.exists_in_array_over_length(text[],integer) to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  time_zone text not null default 'Asia/Tokyo' check (time_zone = 'Asia/Tokyo'),
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.family_members (
  family_id uuid not null references public.families(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.family_role not null,
  status public.member_status not null default 'pending',
  joined_at timestamptz,
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, user_id),
  check ((status = 'active' and joined_at is not null) or status <> 'active')
);
create unique index one_active_family_per_user on public.family_members(user_id) where status = 'active';

create table public.family_invitations (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  token_hash bytea not null unique, short_code_hash bytea not null unique, invited_email_hash bytea not null,
  role public.family_role not null check (role in ('editor', 'viewer')),
  status public.invite_status not null default 'active', expires_at timestamptz not null,
  created_by uuid references auth.users(id) on delete set null, accepted_by uuid references auth.users(id) on delete set null,
  accepted_display_name_snapshot text check (char_length(accepted_display_name_snapshot) between 1 and 80),
  accepted_at timestamptz, approved_by uuid references auth.users(id) on delete set null, approved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (expires_at <= created_at + interval '24 hours 1 minute')
);

create table public.people (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  display_name text not null check (char_length(display_name) between 1 and 120),
  name_kana text check (char_length(name_kana) <= 120), former_name text check (char_length(former_name) <= 120),
  kind public.person_kind not null default 'family_relative', show_in_tree boolean not null default true,
  gender public.gender_value not null default 'unknown', life_status public.life_status not null default 'unknown',
  birth_date date, birth_date_precision public.date_precision not null default 'unknown',
  death_date date, death_date_precision public.date_precision not null default 'unknown',
  nicknames text[] not null default '{}', household_or_group text check (char_length(household_or_group) <= 160),
  phone text check (char_length(phone) <= 30), email text check (char_length(email) <= 254),
  line_display_name text check (char_length(line_display_name) <= 80),
  how_to_recognize text check (char_length(how_to_recognize) <= 500), contact_note text check (char_length(contact_note) <= 500),
  living_person_consent_confirmed boolean not null default false, notes text check (char_length(notes) <= 4000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null,
  check (cardinality(nicknames) <= 10), check (not exists_in_array_over_length(nicknames, 40)),
  check ((birth_date_precision = 'unknown' and birth_date is null) or (birth_date_precision <> 'unknown' and birth_date is not null)),
  check ((death_date_precision = 'unknown' and death_date is null) or (death_date_precision <> 'unknown' and death_date is not null)),
  check (birth_date_precision <> 'year' or extract(month from birth_date) = 1 and extract(day from birth_date) = 1),
  check (birth_date_precision <> 'month' or extract(day from birth_date) = 1),
  check (death_date_precision <> 'year' or extract(month from death_date) = 1 and extract(day from death_date) = 1),
  check (death_date_precision <> 'month' or extract(day from death_date) = 1),
  check (life_status <> 'living' or (death_date is null and death_date_precision = 'unknown')),
  check (birth_date is null or death_date is null or death_date >= birth_date)
);

create table public.deceased_profiles (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), person_id uuid not null references public.people(id),
  posthumous_name text check (char_length(posthumous_name) <= 200), religious_form text check (char_length(religious_form) <= 120),
  denomination text check (char_length(denomination) <= 120), family_customs text check (char_length(family_customs) <= 1000),
  temple_confirmed boolean not null default false, confirmed_on date, confirmed_by_label text check (char_length(confirmed_by_label) <= 120),
  notes text check (char_length(notes) <= 2000), version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null,
  deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);
create unique index deceased_profile_active_unique on public.deceased_profiles(family_id, person_id) where deleted_at is null;

create table public.person_relationships (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  from_person_id uuid not null references public.people(id), to_person_id uuid not null references public.people(id), kind public.relationship_kind not null,
  custom_label text check (char_length(custom_label) <= 80), notes text check (char_length(notes) <= 500),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null,
  check (from_person_id <> to_person_id), check (kind <> 'other' or custom_label is not null)
);
create unique index relationship_active_unique on public.person_relationships(family_id, from_person_id, to_person_id, kind) where deleted_at is null;

create table public.places (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), kind public.place_kind not null,
  name text not null check (char_length(name) between 1 and 160), postal_code text check (postal_code is null or postal_code ~ '^[0-9]{3}-[0-9]{4}$'),
  address text check (char_length(address) <= 300), block_plot text check (char_length(block_plot) <= 200), phone text check (char_length(phone) <= 30),
  website_url text check (website_url is null or website_url ~ '^https://'), external_map_url text check (external_map_url is null or external_map_url ~ '^https://'),
  latitude numeric(9,6) check (latitude between -90 and 90), longitude numeric(9,6) check (longitude between -180 and 180),
  notes text check (char_length(notes) <= 2000), version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null,
  deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);

create table public.person_places (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  person_id uuid not null references public.people(id), place_id uuid not null references public.places(id), kind public.person_place_kind not null,
  started_on date, ended_on date, is_current boolean not null default true, notes text check (char_length(notes) <= 1000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null,
  check (ended_on is null or started_on is null or ended_on >= started_on), check (not is_current or ended_on is null)
);
create index person_places_lookup on public.person_places(family_id, person_id, kind, is_current) where deleted_at is null;

create table public.events (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), kind public.event_kind not null,
  title text not null check (char_length(title) between 1 and 160), status public.event_status not null default 'planned',
  is_candidate boolean not null default false,
  event_date date, event_date_precision public.date_precision not null default 'unknown', end_date date, place_id uuid references public.places(id),
  officiant_or_host text check (char_length(officiant_or_host) <= 160), summary text check (char_length(summary) <= 2000),
  lessons text check (char_length(lessons) <= 2000), notes text check (char_length(notes) <= 4000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null,
  check ((event_date_precision = 'unknown' and event_date is null) or (event_date_precision <> 'unknown' and event_date is not null)),
  check (event_date_precision <> 'year' or extract(month from event_date) = 1 and extract(day from event_date) = 1),
  check (event_date_precision <> 'month' or extract(day from event_date) = 1), check (end_date is null or event_date is null or end_date >= event_date)
);

create table public.event_people (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), event_id uuid not null references public.events(id),
  person_id uuid not null references public.people(id), role_label text not null default '対象者' check (char_length(role_label) between 1 and 80),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);
create unique index event_people_active_unique on public.event_people(family_id,event_id,person_id) where deleted_at is null;

create table public.event_attendees (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), event_id uuid not null references public.events(id),
  person_id uuid references public.people(id), display_name_snapshot text not null check (char_length(display_name_snapshot) between 1 and 120),
  relationship_snapshot text check (char_length(relationship_snapshot) <= 200), status public.attendance_status not null default 'unanswered',
  party_size smallint not null default 1 check (party_size between 1 and 99), notes text check (char_length(notes) <= 1000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);

create table public.event_expenses (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), event_id uuid not null references public.events(id),
  kind public.expense_kind not null, amount_yen bigint check (amount_yen is null or amount_yen between 0 and 100000000),
  paid_by_user_id uuid references auth.users(id) on delete set null, recipient_label text check (char_length(recipient_label) <= 160), paid_on date,
  quantity integer check (quantity between 1 and 10000), item_name text check (char_length(item_name) <= 300),
  vendor_label text check (char_length(vendor_label) <= 160), notes text check (char_length(notes) <= 1000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);

create table public.gift_records (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), kind public.gift_kind not null,
  direction public.gift_direction not null, gift_date date not null, person_id uuid references public.people(id),
  counterpart_snapshot text not null check (char_length(counterpart_snapshot) between 1 and 120), item text check (char_length(item) <= 300),
  quantity integer check (quantity between 1 and 10000), estimated_amount_yen bigint check (estimated_amount_yen between 0 and 100000000),
  vendor_label text check (char_length(vendor_label) <= 160), response text check (char_length(response) <= 1000), notes text check (char_length(notes) <= 2000),
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);

create table public.attachments (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), person_id uuid references public.people(id),
  place_id uuid references public.places(id), event_id uuid references public.events(id), storage_path text not null unique
    check (storage_path ~ '^[0-9a-f-]{36}/(people|places|events)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png)$'),
  mime_type text not null check (mime_type in ('image/jpeg','image/png')), byte_size integer not null check (byte_size between 1 and 5242880),
  width integer not null check (width between 1 and 4096), height integer not null check (height between 1 and 4096), sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  caption text check (char_length(caption) <= 300), version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null,
  check (num_nonnulls(person_id, place_id, event_id) = 1)
);

create table public.reminders (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id), event_id uuid references public.events(id),
  title text not null check (char_length(title) between 1 and 120), due_date date not null,
  notify_offset_days smallint not null check (notify_offset_days between 0 and 3650), notify_time time not null default '09:00', enabled boolean not null default true,
  version integer not null default 1 check (version > 0), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null, deleted_at timestamptz, deleted_by uuid references auth.users(id) on delete set null
);

create table public.user_family_preferences (
  family_id uuid not null references public.families(id), user_id uuid not null references auth.users(id) on delete cascade,
  focus_person_id uuid references public.people(id), notifications_enabled boolean not null default true,
  default_notify_time time not null default '09:00', app_lock_enabled boolean not null default false,
  updated_at timestamptz not null default now(), primary key (family_id,user_id)
);

create table public.activity_logs (
  id bigint generated always as identity primary key, family_id uuid not null references public.families(id),
  actor_user_id uuid references auth.users(id) on delete set null, action text not null,
  entity_type text not null check (entity_type in ('people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders','family_members','family_invitations','families','export_jobs','deletion_jobs')),
  entity_id uuid, changed_fields text[] not null default '{}', occurred_at timestamptz not null default now()
);
create index activity_logs_recent on public.activity_logs(family_id, occurred_at desc);

create table public.export_jobs (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id),
  requested_by uuid references auth.users(id) on delete set null, status public.job_status not null default 'queued',
  format text not null check (format in ('json_v1','csv_v1')), error_code text, created_at timestamptz not null default now(), completed_at timestamptz
);
create table public.deletion_jobs (
  id uuid primary key default gen_random_uuid(), scope public.deletion_scope not null, family_id uuid references public.families(id),
  requested_by uuid references auth.users(id) on delete set null, status public.job_status not null default 'queued',
  execute_after timestamptz not null, error_code text, created_at timestamptz not null default now(), completed_at timestamptz
);

-- authorization helpers
create or replace function private.is_active_family_member(p_family_id uuid, p_user_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.family_members m join public.families f on f.id=m.family_id
    where m.family_id=p_family_id and m.user_id=p_user_id and m.status='active' and f.deleted_at is null)
$$;
create or replace function private.has_family_role(p_family_id uuid, allowed public.family_role[], p_user_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.family_members m join public.families f on f.id=m.family_id
    where m.family_id=p_family_id and m.user_id=p_user_id and m.status='active' and m.role=any(allowed) and f.deleted_at is null)
$$;
create or replace function private.is_family_owner(p_family_id uuid, p_user_id uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$ select private.has_family_role(p_family_id,array['owner']::public.family_role[],p_user_id) $$;
create or replace function private.is_family_writable(p_family_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select private.has_family_role(p_family_id,array['owner','editor']::public.family_role[],auth.uid()) $$;
grant usage on schema private to authenticated;
grant execute on function private.is_active_family_member(uuid,uuid), private.has_family_role(uuid,public.family_role[],uuid), private.is_family_owner(uuid,uuid), private.is_family_writable(uuid) to authenticated;

create or replace function private.set_business_metadata() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    if new.created_by is not null and new.created_by <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
    new.created_by:=auth.uid(); new.updated_by:=auth.uid(); new.created_at:=now(); new.updated_at:=now(); new.version:=coalesce(new.version,1);
  else
    if new.id<>old.id or new.family_id<>old.family_id or new.created_by is distinct from old.created_by or new.created_at<>old.created_at then raise exception 'IMMUTABLE_FIELD' using errcode='22023'; end if;
    new.version:=old.version+1; new.updated_by:=auth.uid(); new.updated_at:=now();
    if old.deleted_at is null and new.deleted_at is not null then new.deleted_by:=auth.uid(); end if;
    if old.deleted_at is not null and new.deleted_at is null then new.deleted_by:=null; end if;
  end if;
  return new;
end $$;

create or replace function private.touch_profile() returns trigger language plpgsql set search_path='' as $$
begin
  if new.id<>old.id or new.created_at<>old.created_at then raise exception 'IMMUTABLE_FIELD' using errcode='22023'; end if;
  new.updated_at:=now(); return new;
end $$;
create trigger profile_touch before update on public.profiles for each row execute function private.touch_profile();

create or replace function private.touch_family() returns trigger language plpgsql set search_path='' as $$
begin
  if new.id<>old.id or new.created_by is distinct from old.created_by or new.time_zone<>old.time_zone or new.created_at<>old.created_at or new.deleted_at is distinct from old.deleted_at then raise exception 'IMMUTABLE_FIELD' using errcode='22023'; end if;
  new.version:=old.version+1; new.updated_at:=now(); return new;
end $$;
create trigger family_touch before update on public.families for each row execute function private.touch_family();

create or replace function private.check_preference() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' and (new.family_id<>old.family_id or new.user_id<>old.user_id) then raise exception 'IMMUTABLE_FIELD' using errcode='22023'; end if;
  if not exists(select 1 from public.family_members where family_id=new.family_id and user_id=new.user_id and status='active') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if new.focus_person_id is not null and not exists(select 1 from public.people where id=new.focus_person_id and family_id=new.family_id and deleted_at is null) then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if;
  new.updated_at:=now(); return new;
end $$;
create trigger preference_guard before insert or update on public.user_family_preferences for each row execute function private.check_preference();

create or replace function private.check_same_family_refs() returns trigger language plpgsql set search_path='' as $$
declare f uuid;
begin
  if tg_table_name='deceased_profiles' then select family_id into f from public.people where id=new.person_id;
  elsif tg_table_name='person_places' then
    if not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id) or not exists(select 1 from public.places where id=new.place_id and family_id=new.family_id) then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if; return new;
  elsif tg_table_name='event_people' then
    if not exists(select 1 from public.events where id=new.event_id and family_id=new.family_id) or not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id) then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if; return new;
  elsif tg_table_name='event_attendees' then
    if not exists(select 1 from public.events where id=new.event_id and family_id=new.family_id) or (new.person_id is not null and not exists(select 1 from public.people where id=new.person_id and family_id=new.family_id)) then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if; return new;
  elsif tg_table_name='event_expenses' then select family_id into f from public.events where id=new.event_id;
  elsif tg_table_name='events' and new.place_id is not null then select family_id into f from public.places where id=new.place_id;
  elsif tg_table_name='gift_records' and new.person_id is not null then select family_id into f from public.people where id=new.person_id;
  elsif tg_table_name='reminders' and new.event_id is not null then select family_id into f from public.events where id=new.event_id;
  elsif tg_table_name='attachments' then
    if new.person_id is not null then select family_id into f from public.people where id=new.person_id;
    elsif new.place_id is not null then select family_id into f from public.places where id=new.place_id;
    else select family_id into f from public.events where id=new.event_id; end if;
  else return new; end if;
  if f is distinct from new.family_id then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if;
  if tg_table_name='attachments' then
    if split_part(new.storage_path,'/',1)::uuid <> new.family_id then raise exception 'CROSS_FAMILY_STORAGE_PATH' using errcode='23514'; end if;
    if new.person_id is not null and (split_part(new.storage_path,'/',2)<>'people' or split_part(new.storage_path,'/',3)::uuid<>new.person_id) then raise exception 'INVALID_STORAGE_PATH' using errcode='23514'; end if;
    if new.place_id is not null and (split_part(new.storage_path,'/',2)<>'places' or split_part(new.storage_path,'/',3)::uuid<>new.place_id) then raise exception 'INVALID_STORAGE_PATH' using errcode='23514'; end if;
    if new.event_id is not null and (split_part(new.storage_path,'/',2)<>'events' or split_part(new.storage_path,'/',3)::uuid<>new.event_id) then raise exception 'INVALID_STORAGE_PATH' using errcode='23514'; end if;
  end if;
  if tg_table_name='deceased_profiles' and not exists(select 1 from public.people where id=new.person_id and life_status='deceased') then raise exception 'PERSON_NOT_DECEASED' using errcode='23514'; end if;
  return new;
end $$;

create or replace function private.check_relationship() returns trigger language plpgsql set search_path='' as $$
begin
  if not exists(select 1 from public.people where id=new.from_person_id and family_id=new.family_id) or not exists(select 1 from public.people where id=new.to_person_id and family_id=new.family_id) then raise exception 'CROSS_FAMILY_REFERENCE' using errcode='23514'; end if;
  if new.kind in ('spouse','partner','sibling') then
    select least(new.from_person_id,new.to_person_id), greatest(new.from_person_id,new.to_person_id)
      into new.from_person_id,new.to_person_id;
  end if;
  if new.kind in ('parent_child','adopted_parent_child','step_parent_child') and exists(
    with recursive ancestors(id) as (
      select new.to_person_id union select r.to_person_id from public.person_relationships r join ancestors a on r.from_person_id=a.id
      where r.family_id=new.family_id and r.kind in ('parent_child','adopted_parent_child','step_parent_child') and r.deleted_at is null and r.id<>new.id)
    select 1 from ancestors where id=new.from_person_id) then raise exception 'RELATIONSHIP_CYCLE' using errcode='23514'; end if;
  return new;
end $$;

create or replace function private.audit_business_change() returns trigger language plpgsql security definer set search_path='' as $$
declare fields text[] := '{}'; action_name text := lower(tg_op); k text;
begin
  if tg_op='UPDATE' then
    for k in select n.key from jsonb_each(to_jsonb(new)) n where (to_jsonb(new)->n.key) is distinct from (to_jsonb(old)->n.key) loop fields:=array_append(fields,k); end loop;
    if old.deleted_at is null and new.deleted_at is not null then action_name:='soft_delete'; elsif old.deleted_at is not null and new.deleted_at is null then action_name:='restore'; end if;
  end if;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id,changed_fields)
  values(new.family_id,auth.uid(),action_name,tg_table_name,new.id,fields);
  return new;
end $$;

do $$ declare t text; begin
  foreach t in array array['people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders'] loop
    execute format('create trigger %I_metadata before insert or update on public.%I for each row execute function private.set_business_metadata()',t,t);
    execute format('create trigger %I_audit after insert or update on public.%I for each row execute function private.audit_business_change()',t,t);
  end loop;
end $$;
create trigger deceased_profile_refs before insert or update on public.deceased_profiles for each row execute function private.check_same_family_refs();
create trigger person_place_refs before insert or update on public.person_places for each row execute function private.check_same_family_refs();
create trigger event_people_refs before insert or update on public.event_people for each row execute function private.check_same_family_refs();
create trigger event_attendee_refs before insert or update on public.event_attendees for each row execute function private.check_same_family_refs();
create trigger event_expense_refs before insert or update on public.event_expenses for each row execute function private.check_same_family_refs();
create trigger event_refs before insert or update on public.events for each row execute function private.check_same_family_refs();
create trigger gift_record_refs before insert or update on public.gift_records for each row execute function private.check_same_family_refs();
create trigger reminder_refs before insert or update on public.reminders for each row execute function private.check_same_family_refs();
create trigger attachment_refs before insert or update on public.attachments for each row execute function private.check_same_family_refs();
create trigger relationship_refs before insert or update on public.person_relationships for each row execute function private.check_relationship();

create or replace function private.prevent_last_owner_loss() returns trigger language plpgsql set search_path='' as $$
begin
  if old.role='owner' and old.status='active' and (tg_op='DELETE' or new.role<>'owner' or new.status<>'active') and not exists(
    select 1 from public.family_members m where m.family_id=old.family_id and m.user_id<>old.user_id and m.role='owner' and m.status='active')
  then raise exception 'OWNER_TRANSFER_REQUIRED' using errcode='23514'; end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger family_member_owner_guard before update or delete on public.family_members for each row execute function private.prevent_last_owner_loss();

-- RPCs are the only supported membership/invitation mutation path.
create or replace function public.create_family(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'VALIDATION_FAILED' using errcode='22023'; end if;
  if exists(select 1 from public.family_members where user_id=auth.uid() and status='active') then raise exception 'MEMBER_ALREADY_ACTIVE' using errcode='23505'; end if;
  insert into public.families(name,created_by) values(trim(p_name),auth.uid()) returning id into fid;
  insert into public.family_members(family_id,user_id,role,status,joined_at) values(fid,auth.uid(),'owner','active',now());
  insert into public.user_family_preferences(family_id,user_id) values(fid,auth.uid());
  return fid;
end $$;
revoke all on function public.create_family(text) from public, anon;
grant execute on function public.create_family(text) to authenticated;

create or replace function public.create_family_invitation(p_family_id uuid,p_token_hash_hex text,p_short_code_hash_hex text,p_invited_email_hash_hex text,p_role public.family_role) returns uuid
language plpgsql security definer set search_path='' as $$ declare iid uuid;
begin
  if not private.is_family_owner(p_family_id,auth.uid()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_role not in ('editor','viewer') or p_token_hash_hex !~ '^[0-9a-f]{64}$' or p_short_code_hash_hex !~ '^[0-9a-f]{64}$' or p_invited_email_hash_hex !~ '^[0-9a-f]{64}$' then raise exception 'VALIDATION_FAILED' using errcode='22023'; end if;
  if (select count(*) from public.family_invitations where family_id=p_family_id and created_by=auth.uid() and created_at>now()-interval '1 day')>=10 then raise exception 'INVITE_RATE_LIMITED' using errcode='P0001'; end if;
  update public.family_invitations set status='expired',updated_at=now() where status='active' and expires_at<=now();
  insert into public.family_invitations(family_id,token_hash,short_code_hash,invited_email_hash,role,expires_at,created_by)
  values(p_family_id,decode(p_token_hash_hex,'hex'),decode(p_short_code_hash_hex,'hex'),decode(p_invited_email_hash_hex,'hex'),p_role,now()+interval '24 hours',auth.uid()) returning id into iid;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id) values(p_family_id,auth.uid(),'invite','family_invitations',iid);
  return iid;
end $$;

create or replace function public.accept_family_invitation(p_hash_hex text,p_is_short_code boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare inv public.family_invitations%rowtype; jwt_email text; accepted_name text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_hash_hex !~ '^[0-9a-f]{64}$' then raise exception 'INVITE_INVALID' using errcode='22023'; end if;
  if exists(select 1 from public.family_members where user_id=auth.uid() and status='active') then raise exception 'MEMBER_ALREADY_ACTIVE' using errcode='23505'; end if;
  select * into inv from public.family_invitations where (case when p_is_short_code then short_code_hash else token_hash end)=decode(p_hash_hex,'hex') for update;
  if not found then raise exception 'INVITE_INVALID' using errcode='P0001'; end if;
  if inv.status<>'active' then raise exception 'INVITE_ALREADY_USED' using errcode='P0001'; end if;
  if inv.expires_at<=now() then raise exception 'INVITE_EXPIRED' using errcode='P0001'; end if;
  jwt_email:=lower(trim(coalesce(auth.jwt()->>'email','')));
  if jwt_email='' or extensions.digest(jwt_email,'sha256')<>inv.invited_email_hash then raise exception 'INVITE_EMAIL_MISMATCH' using errcode='42501'; end if;
  select display_name into accepted_name from public.profiles where id=auth.uid();
  if accepted_name is null then raise exception 'PROFILE_REQUIRED' using errcode='P0001'; end if;
  insert into public.family_members(family_id,user_id,role,status,invited_by) values(inv.family_id,auth.uid(),inv.role,'pending',inv.created_by);
  update public.family_invitations set status='accepted',accepted_by=auth.uid(),accepted_display_name_snapshot=accepted_name,accepted_at=now(),updated_at=now() where id=inv.id;
  return inv.id;
end $$;

create or replace function public.approve_family_member(p_invitation_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare inv public.family_invitations%rowtype;
begin
  select * into inv from public.family_invitations where id=p_invitation_id for update;
  if not found or not private.is_family_owner(inv.family_id,auth.uid()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if inv.status<>'accepted' or inv.accepted_by is null then raise exception 'INVITE_INVALID' using errcode='P0001'; end if;
  if exists(select 1 from public.family_members where user_id=inv.accepted_by and status='active') then raise exception 'MEMBER_ALREADY_ACTIVE' using errcode='23505'; end if;
  update public.family_members set status='active',joined_at=now(),updated_at=now() where family_id=inv.family_id and user_id=inv.accepted_by and status='pending';
  if not found then raise exception 'INVITE_INVALID' using errcode='P0001'; end if;
  insert into public.user_family_preferences(family_id,user_id) values(inv.family_id,inv.accepted_by) on conflict do nothing;
  update public.family_invitations set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=inv.id;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id) values(inv.family_id,auth.uid(),'approve','family_members',inv.accepted_by);
end $$;

create or replace function public.revoke_family_invitation(p_invitation_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare inv public.family_invitations%rowtype;
begin
  select * into inv from public.family_invitations where id=p_invitation_id for update;
  if not found or not private.is_family_owner(inv.family_id,auth.uid()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if inv.status not in ('active','accepted') then raise exception 'INVITE_ALREADY_USED' using errcode='P0001'; end if;
  delete from public.family_members where family_id=inv.family_id and user_id=inv.accepted_by and status='pending';
  update public.family_invitations set status='revoked',updated_at=now() where id=inv.id;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id) values(inv.family_id,auth.uid(),'revoke','family_invitations',inv.id);
end $$;

create or replace function public.change_family_member_role(p_family_id uuid,p_user_id uuid,p_role public.family_role) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_family_owner(p_family_id,auth.uid()) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.family_members set role=p_role,updated_at=now() where family_id=p_family_id and user_id=p_user_id and status='active';
  if not found then raise exception 'FAMILY_NOT_FOUND' using errcode='P0001'; end if;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id,changed_fields) values(p_family_id,auth.uid(),'update','family_members',p_user_id,array['role']);
end $$;

revoke all on function public.create_family_invitation(uuid,text,text,text,public.family_role), public.accept_family_invitation(text,boolean), public.approve_family_member(uuid), public.revoke_family_invitation(uuid), public.change_family_member_role(uuid,uuid,public.family_role) from public,anon;
grant execute on function public.create_family_invitation(uuid,text,text,text,public.family_role), public.accept_family_invitation(text,boolean), public.approve_family_member(uuid), public.revoke_family_invitation(uuid), public.change_family_member_role(uuid,uuid,public.family_role) to authenticated;

-- RLS. No DELETE policy: normal deletion is a versioned soft delete.
alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invitations enable row level security;
alter table public.user_family_preferences enable row level security;
create policy profile_self_read on public.profiles for select to authenticated using (id=auth.uid());
create policy profile_family_read on public.profiles for select to authenticated using (exists(select 1 from public.family_members mine join public.family_members theirs on theirs.family_id=mine.family_id where mine.user_id=auth.uid() and mine.status='active' and theirs.user_id=profiles.id and theirs.status='active'));
create policy profile_self_insert on public.profiles for insert to authenticated with check (id=auth.uid());
create policy profile_self_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy families_read on public.families for select to authenticated using(private.is_active_family_member(id));
create policy families_owner_update on public.families for update to authenticated using(private.is_family_owner(id)) with check(private.is_family_owner(id));
create policy members_read on public.family_members for select to authenticated using(private.is_active_family_member(family_id) or user_id=auth.uid());
create policy invitations_owner_read on public.family_invitations for select to authenticated using(private.is_family_owner(family_id));
create policy preferences_self_all on public.user_family_preferences for all to authenticated using(user_id=auth.uid() and private.is_active_family_member(family_id)) with check(user_id=auth.uid() and private.is_active_family_member(family_id));

do $$ declare t text; begin
  foreach t in array array['people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('create policy %I_read on public.%I for select to authenticated using (private.is_active_family_member(family_id) and deleted_at is null)',t,t);
    execute format('create policy %I_insert on public.%I for insert to authenticated with check (private.is_family_writable(family_id))',t,t);
    execute format('create policy %I_update on public.%I for update to authenticated using (private.is_family_writable(family_id)) with check (private.is_family_writable(family_id))',t,t);
  end loop;
end $$;
alter table public.activity_logs enable row level security;
alter table public.export_jobs enable row level security;
alter table public.deletion_jobs enable row level security;
create policy activity_owner_read on public.activity_logs for select to authenticated using(private.is_family_owner(family_id) and occurred_at>=now()-interval '180 days');
create policy export_owner_read on public.export_jobs for select to authenticated using(requested_by=auth.uid() and private.is_family_owner(family_id));
create policy deletion_requester_read on public.deletion_jobs for select to authenticated using(requested_by=auth.uid());

-- Private object bucket and path-based Storage authorization.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('family-private','family-private',false,5242880,array['image/jpeg','image/png']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy family_storage_read on storage.objects for select to authenticated using(bucket_id='family-private' and private.is_active_family_member((storage.foldername(name))[1]::uuid));
create policy family_storage_insert on storage.objects for insert to authenticated with check(bucket_id='family-private' and (storage.foldername(name))[2] in ('people','places','events') and private.is_family_writable((storage.foldername(name))[1]::uuid));

do $$ declare t text; begin
  foreach t in array array['profiles','families','family_members','family_invitations','user_family_preferences','people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders','activity_logs','export_jobs','deletion_jobs'] loop execute format('alter table public.%I force row level security',t); end loop;
end $$;

revoke all on all tables in schema public from anon;
grant select,insert,update on public.profiles to authenticated;
grant select on public.families to authenticated;
grant update(name) on public.families to authenticated;
grant select on public.family_members,public.family_invitations to authenticated;
grant select,insert,update,delete on public.user_family_preferences to authenticated;
-- Business writes are intentionally not granted to the client role. Mutations that
-- can overwrite shared family history must pass through version-checked,
-- security-definer RPCs (installed by the app-write migration).
grant select on public.people,public.deceased_profiles,public.person_relationships,public.places,public.person_places,public.events,public.event_people,public.event_attendees,public.event_expenses,public.gift_records,public.attachments,public.reminders to authenticated;
grant select on public.activity_logs,public.export_jobs,public.deletion_jobs to authenticated;
