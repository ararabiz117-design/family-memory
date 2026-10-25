begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(10);

select is((
  select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(array['profiles','families','family_members','family_invitations','user_family_preferences','people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders','activity_logs','export_jobs','deletion_jobs']) and not c.relrowsecurity
),0,'all application tables enable RLS');

select is((
  select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(array['profiles','families','family_members','family_invitations','user_family_preferences','people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders','activity_logs','export_jobs','deletion_jobs']) and not c.relforcerowsecurity
),0,'all application tables force RLS');

select is((select count(*)::int from information_schema.role_table_grants where grantee='anon' and table_schema='public'),0,'anon has no public table grants');
select is((select count(*)::int from pg_policies where schemaname in ('public','storage') and 'anon'=any(roles)),0,'no policy targets anon');
select ok((select not public from storage.buckets where id='family-private'),'family storage is private');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('is_active_family_member','has_family_role','is_family_owner','is_family_writable') and p.prosecdef),4,'RLS helpers are security definer');
select has_column('public','family_invitations','invited_email_hash','invites are bound to an intended email');
select has_column('public','family_invitations','accepted_display_name_snapshot','owners can verify the pending member name');
select is((select count(*)::int from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('family_storage_update','family_storage_delete')),0,'client roles cannot overwrite or physically delete stored evidence');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename=any(array['people','deceased_profiles','person_relationships','places','person_places','events','event_people','event_attendees','event_expenses','gift_records','attachments','reminders']) and policyname like '%_read' and qual not ilike '%deleted_at IS NULL%'),0,'business read policies hide soft-deleted rows');

select * from finish();
rollback;
