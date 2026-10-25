-- Account/family lifecycle, retention and owner-only export.
-- Destructive work is queued for 30 days and executed only by the service-role worker.

alter table public.deletion_jobs
  add column if not exists target_user_id uuid,
  add column if not exists target_family_id uuid,
  add column if not exists started_at timestamptz;

alter table public.deletion_jobs drop constraint if exists deletion_jobs_family_id_fkey;
alter table public.deletion_jobs
  add constraint deletion_jobs_family_id_fkey foreign key (family_id)
  references public.families(id) on delete set null;

alter table public.deletion_jobs
  drop constraint if exists deletion_job_target_check;
alter table public.deletion_jobs
  add constraint deletion_job_target_check check (
    (scope = 'account' and target_user_id is not null and target_family_id is null)
    or (scope = 'family' and target_family_id is not null and target_user_id is null)
    or scope = 'record'
  ) not valid;
alter table public.deletion_jobs validate constraint deletion_job_target_check;

create unique index if not exists deletion_jobs_one_open_account
  on public.deletion_jobs(target_user_id)
  where scope = 'account' and status in ('queued','processing');
create unique index if not exists deletion_jobs_one_open_family
  on public.deletion_jobs(target_family_id)
  where scope = 'family' and status in ('queued','processing');
create index if not exists deletion_jobs_due on public.deletion_jobs(execute_after, scope)
  where status = 'queued';

-- A family can only enter the deleted state through an owner-authorized RPC.
-- Restoration is intentionally absent from the beta lifecycle contract.
create or replace function private.touch_family() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.id<>old.id or new.created_by is distinct from old.created_by
     or new.time_zone<>old.time_zone or new.created_at<>old.created_at then
    raise exception 'IMMUTABLE_FIELD' using errcode='22023';
  end if;
  if new.deleted_at is distinct from old.deleted_at then
    if old.deleted_at is not null or new.deleted_at is null
       or not private.is_family_owner(old.id,auth.uid()) then
      raise exception 'FORBIDDEN' using errcode='42501';
    end if;
  end if;
  new.version:=old.version+1;
  new.updated_at:=now();
  return new;
end $$;

-- The worker must be able to remove the final owner during physical purge.
-- No authenticated user receives EXECUTE on worker RPCs below.
create or replace function private.prevent_last_owner_loss() returns trigger
language plpgsql set search_path='' as $$
begin
  if coalesce(auth.role(),'')='service_role' then
    return case when tg_op='DELETE' then old else new end;
  end if;
  if old.role='owner' and old.status='active'
     and (tg_op='DELETE' or new.role<>'owner' or new.status<>'active')
     and not exists(
       select 1 from public.family_members m
       where m.family_id=old.family_id and m.user_id<>old.user_id
         and m.role='owner' and m.status='active'
     ) then
    raise exception 'OWNER_TRANSFER_REQUIRED' using errcode='23514';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

create or replace function private.assert_service_role() returns void
language plpgsql stable security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
end $$;
revoke all on function private.assert_service_role() from public,anon,authenticated;

-- Destructive requests require a newly-issued session. The app obtains it by
-- asking the signed-in user to enter a fresh email OTP immediately beforehand.
create or replace function private.assert_recent_sign_in(
  p_max_age_seconds integer default 600
) returns void
language plpgsql stable set search_path='' as $$
declare
  issued_at_text text:=coalesce(
    auth.jwt()->>'iat',
    nullif(current_setting('request.jwt.claim.iat',true),'')
  );
begin
  if p_max_age_seconds not between 60 and 900
     or issued_at_text is null
     or issued_at_text !~ '^\d+(\.\d+)?$'
     or to_timestamp(issued_at_text::double precision)
        < now()-make_interval(secs=>p_max_age_seconds) then
    raise exception 'REAUTHENTICATION_REQUIRED' using errcode='42501';
  end if;
end $$;
revoke all on function private.assert_recent_sign_in(integer)
  from public,anon,authenticated;

create or replace function public.request_account_deletion_v1() returns uuid
language plpgsql security definer set search_path='' as $$
declare
  uid uuid:=auth.uid();
  jid uuid;
  membership record;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  perform private.assert_recent_sign_in();

  select id into jid from public.deletion_jobs
  where scope='account' and target_user_id=uid and status in ('queued','processing')
  order by created_at desc limit 1;
  if jid is not null then return jid; end if;

  if exists(
    select 1 from public.family_members mine
    join public.families f on f.id=mine.family_id and f.deleted_at is null
    where mine.user_id=uid and mine.status='active' and mine.role='owner'
      and not exists(
        select 1 from public.family_members other
        where other.family_id=mine.family_id and other.user_id<>uid
          and other.status='active' and other.role='owner'
      )
  ) then
    raise exception 'OWNER_TRANSFER_REQUIRED' using errcode='23514';
  end if;

  insert into public.deletion_jobs(scope,target_user_id,requested_by,status,execute_after)
  values('account',uid,uid,'queued',now()+interval '30 days') returning id into jid;

  for membership in
    select m.family_id from public.family_members m
    join public.families f on f.id=m.family_id and f.deleted_at is null
    where m.user_id=uid and m.status='active'
  loop
    insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id)
    values(membership.family_id,uid,'account_deletion_requested','deletion_jobs',jid);
  end loop;

  update public.family_members m set status='suspended',updated_at=now()
  where m.user_id=uid and m.status='active'
    and exists(select 1 from public.families f where f.id=m.family_id and f.deleted_at is null);
  return jid;
end $$;

create or replace function public.request_family_deletion_v1(p_family_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare jid uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  perform private.assert_recent_sign_in();

  select id into jid from public.deletion_jobs
  where scope='family' and target_family_id=p_family_id
    and requested_by=auth.uid() and status in ('queued','processing')
  order by created_at desc limit 1;
  if jid is not null then return jid; end if;

  if not private.is_family_owner(p_family_id,auth.uid()) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  insert into public.deletion_jobs(
    scope,family_id,target_family_id,requested_by,status,execute_after
  ) values(
    'family',p_family_id,p_family_id,auth.uid(),'queued',now()+interval '30 days'
  ) returning id into jid;
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id)
  values(p_family_id,auth.uid(),'family_deletion_requested','deletion_jobs',jid);
  update public.families set deleted_at=now() where id=p_family_id and deleted_at is null;
  if not found then raise exception 'FAMILY_NOT_FOUND' using errcode='P0001'; end if;
  return jid;
end $$;

-- Text and metadata export only. Attachment binaries and invitation token/email hashes
-- are deliberately excluded. The Edge Function serializes json_v1 or csv_v1.
create or replace function public.export_family_data_v1(
  p_family_id uuid,
  p_format text default 'json_v1'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare jid uuid; payload jsonb;
begin
  if not private.is_family_owner(p_family_id,auth.uid()) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_format not in ('json_v1','csv_v1') then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;

  insert into public.export_jobs(family_id,requested_by,status,format,completed_at)
  values(p_family_id,auth.uid(),'completed',p_format,now()) returning id into jid;

  payload:=jsonb_build_object(
    'schemaVersion','family-memory-export-v1',
    'exportedAt',now(),
    'family',(select to_jsonb(f)-'deleted_at' from public.families f where f.id=p_family_id),
    'members',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',m.user_id,'display_name',p.display_name,'role',m.role,
        'status',m.status,'joined_at',m.joined_at
      ) order by m.created_at)
      from public.family_members m left join public.profiles p on p.id=m.user_id
      where m.family_id=p_family_id
    ),'[]'::jsonb),
    'people',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.people x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'deceased_profiles',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.deceased_profiles x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'person_relationships',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.person_relationships x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'places',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.places x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'person_places',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.person_places x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.events x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'event_people',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.event_people x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'event_attendees',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.event_attendees x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'event_expenses',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.event_expenses x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'gift_records',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.gift_records x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'reminders',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.reminders x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb),
    'attachments',coalesce((select jsonb_agg(to_jsonb(x)-'deleted_by' order by x.created_at) from public.attachments x where x.family_id=p_family_id and x.deleted_at is null),'[]'::jsonb)
  );
  insert into public.activity_logs(family_id,actor_user_id,action,entity_type,entity_id)
  values(p_family_id,auth.uid(),'export','export_jobs',jid);
  return jsonb_build_object('jobId',jid,'format',p_format,'data',payload);
end $$;

revoke all on function public.request_account_deletion_v1(),
  public.request_family_deletion_v1(uuid),public.export_family_data_v1(uuid,text)
  from public,anon;
grant execute on function public.request_account_deletion_v1(),
  public.request_family_deletion_v1(uuid),public.export_family_data_v1(uuid,text)
  to authenticated;

-- Worker RPCs. These are in the exposed schema for Supabase RPC transport, but only
-- service_role has EXECUTE and every function also verifies the signed JWT role.
create or replace function public.claim_due_deletion_jobs_v1(p_limit integer default 20)
returns table(id uuid,scope public.deletion_scope,target_user_id uuid,target_family_id uuid)
language plpgsql security definer set search_path='' as $$
begin
  perform private.assert_service_role();
  return query
  with due as (
    select j.id from public.deletion_jobs j
    where j.status='queued' and j.execute_after<=now()
      and j.scope in ('account','family')
      and (
        j.scope<>'account' or not exists(
          select 1 from public.family_members mine
          where mine.user_id=j.target_user_id and mine.role='owner' and mine.status='active'
            and not exists(
              select 1 from public.family_members other
              where other.family_id=mine.family_id and other.user_id<>mine.user_id
                and other.role='owner' and other.status='active'
            )
        )
      )
    order by case when j.scope='family' then 0 else 1 end,j.execute_after,j.created_at
    limit greatest(1,least(coalesce(p_limit,20),100)) for update skip locked
  ), claimed as (
    update public.deletion_jobs j set status='processing',started_at=now(),error_code=null
    from due where j.id=due.id
    returning j.id,j.scope,j.target_user_id,j.target_family_id
  )
  select c.id,c.scope,c.target_user_id,c.target_family_id from claimed c;
end $$;

create or replace function public.list_family_storage_paths_v1(
  p_job_id uuid,p_limit integer default 500
) returns table(storage_path text)
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
  perform private.assert_service_role();
  select target_family_id into fid from public.deletion_jobs
  where id=p_job_id and scope='family' and status='processing';
  if fid is null then raise exception 'JOB_INVALID' using errcode='22023'; end if;
  return query select o.name from storage.objects o
    where o.bucket_id='family-private' and split_part(o.name,'/',1)=fid::text
    order by o.name limit greatest(1,least(coalesce(p_limit,500),1000));
end $$;

create or replace function public.purge_family_v1(p_job_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
  perform private.assert_service_role();
  select target_family_id into fid from public.deletion_jobs
  where id=p_job_id and scope='family' and status='processing' for update;
  if fid is null then raise exception 'JOB_INVALID' using errcode='22023'; end if;
  if exists(select 1 from storage.objects o where o.bucket_id='family-private' and split_part(o.name,'/',1)=fid::text) then
    raise exception 'STORAGE_NOT_EMPTY' using errcode='55000';
  end if;

  delete from public.user_family_preferences where family_id=fid;
  delete from public.attachments where family_id=fid;
  delete from public.reminders where family_id=fid;
  delete from public.gift_records where family_id=fid;
  delete from public.event_expenses where family_id=fid;
  delete from public.event_attendees where family_id=fid;
  delete from public.event_people where family_id=fid;
  delete from public.events where family_id=fid;
  delete from public.person_places where family_id=fid;
  delete from public.person_relationships where family_id=fid;
  delete from public.deceased_profiles where family_id=fid;
  delete from public.people where family_id=fid;
  delete from public.places where family_id=fid;
  delete from public.family_invitations where family_id=fid;
  delete from public.activity_logs where family_id=fid;
  delete from public.family_members where family_id=fid;
  delete from public.export_jobs where family_id=fid;
  delete from public.families where id=fid;
  if not found then raise exception 'FAMILY_NOT_FOUND' using errcode='P0001'; end if;
  update public.deletion_jobs set status='completed',completed_at=now(),family_id=null
  where id=p_job_id;
end $$;

create or replace function public.complete_account_deletion_job_v1(p_job_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.assert_service_role();
  update public.deletion_jobs set status='completed',completed_at=now(),requested_by=null
  where id=p_job_id and scope='account' and status='processing';
  if not found then raise exception 'JOB_INVALID' using errcode='22023'; end if;
end $$;

create or replace function public.fail_deletion_job_v1(p_job_id uuid,p_error_code text) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.assert_service_role();
  if p_error_code is null or p_error_code !~ '^[A-Z0-9_]{1,64}$' then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  update public.deletion_jobs set status='failed',completed_at=now(),error_code=p_error_code
  where id=p_job_id and status='processing';
  if not found then raise exception 'JOB_INVALID' using errcode='22023'; end if;
end $$;

create or replace function public.list_storage_cleanup_candidates_v1(p_limit integer default 500)
returns table(storage_path text,remove_attachment_metadata boolean)
language plpgsql security definer set search_path='' as $$
begin
  perform private.assert_service_role();
  return query
    select o.name,(a.id is not null)
    from storage.objects o
    left join public.attachments a on a.storage_path=o.name
    where o.bucket_id='family-private'
      and (
        (a.id is null and o.created_at<=now()-interval '24 hours')
        or (a.deleted_at is not null and a.deleted_at<=now()-interval '30 days')
      )
      and not exists(
        select 1 from public.deletion_jobs j
        where j.scope='family' and j.status in ('queued','processing')
          and j.target_family_id::text=split_part(o.name,'/',1)
      )
    order by o.created_at limit greatest(1,least(coalesce(p_limit,500),1000));
end $$;

create or replace function public.finalize_storage_cleanup_v1(p_storage_paths text[]) returns integer
language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
  perform private.assert_service_role();
  if coalesce(cardinality(p_storage_paths),0)>1000 then
    raise exception 'VALIDATION_FAILED' using errcode='22023';
  end if;
  delete from public.attachments a
  where a.storage_path=any(coalesce(p_storage_paths,'{}'::text[]))
    and a.deleted_at is not null and a.deleted_at<=now()-interval '30 days';
  get diagnostics removed=row_count;
  return removed;
end $$;

revoke all on function public.claim_due_deletion_jobs_v1(integer),
  public.list_family_storage_paths_v1(uuid,integer),public.purge_family_v1(uuid),
  public.complete_account_deletion_job_v1(uuid),public.fail_deletion_job_v1(uuid,text),
  public.list_storage_cleanup_candidates_v1(integer),public.finalize_storage_cleanup_v1(text[])
  from public,anon,authenticated;
grant execute on function public.claim_due_deletion_jobs_v1(integer),
  public.list_family_storage_paths_v1(uuid,integer),public.purge_family_v1(uuid),
  public.complete_account_deletion_job_v1(uuid),public.fail_deletion_job_v1(uuid,text),
  public.list_storage_cleanup_candidates_v1(integer),public.finalize_storage_cleanup_v1(text[])
  to service_role;
