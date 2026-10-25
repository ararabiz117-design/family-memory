begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(26);

-- Self-contained fictional fixtures. The surrounding transaction always rolls them back.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner.a@example.invalid',extensions.crypt('local-only',extensions.gen_salt('bf')),now(),'{}','{}',now(),now()),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','editor.b@example.invalid',extensions.crypt('local-only',extensions.gen_salt('bf')),now(),'{}','{}',now(),now()),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','viewer.c@example.invalid',extensions.crypt('local-only',extensions.gen_salt('bf')),now(),'{}','{}',now(),now()),
 ('10000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other.d@example.invalid',extensions.crypt('local-only',extensions.gen_salt('bf')),now(),'{}','{}',now(),now())
on conflict (id) do nothing;
insert into public.profiles(id,display_name) values
 ('10000000-0000-4000-8000-000000000001','青葉 花'),
 ('10000000-0000-4000-8000-000000000002','青葉 空'),
 ('10000000-0000-4000-8000-000000000003','青葉 光'),
 ('10000000-0000-4000-8000-000000000004','若葉 海')
on conflict (id) do nothing;
insert into public.families(id,name,created_by) values
 ('20000000-0000-4000-8000-000000000001','青葉家（架空）','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000002','若葉家（架空）','10000000-0000-4000-8000-000000000004')
on conflict (id) do nothing;
insert into public.family_members(family_id,user_id,role,status,joined_at) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','owner','active',now()),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','editor','active',now()),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','viewer','active',now()),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004','owner','active',now())
on conflict (family_id,user_id) do nothing;

select has_column('public','deletion_jobs','target_user_id','account purge target is durable');
select has_column('public','deletion_jobs','target_family_id','family purge target is durable');
select has_column('public','deletion_jobs','started_at','worker claim time is recorded');
select has_function('public','request_account_deletion_v1',array[]::text[],'account deletion request exists');
select has_function('public','request_family_deletion_v1',array['uuid'],'family deletion request exists');
select has_function('public','export_family_data_v1',array['uuid','text'],'owner export exists');
select has_function('public','claim_due_deletion_jobs_v1',array['integer'],'worker claim exists');
select has_function('public','list_family_storage_paths_v1',array['uuid','integer'],'family storage purge listing exists');
select has_function('public','purge_family_v1',array['uuid'],'family purge exists');
select has_function('public','complete_account_deletion_job_v1',array['uuid'],'account completion exists');
select has_function('public','fail_deletion_job_v1',array['uuid','text'],'worker failure recording exists');
select has_function('public','list_storage_cleanup_candidates_v1',array['integer'],'orphan cleanup listing exists');
select has_function('public','finalize_storage_cleanup_v1',array['text[]'],'orphan metadata cleanup exists');
select has_function('private','assert_recent_sign_in',array['integer'],'destructive requests require recent authentication');

select function_privs_are('public','export_family_data_v1',array['uuid','text'],'authenticated',array['EXECUTE'],'authenticated callers reach owner-checked export RPC');
select function_privs_are('public','claim_due_deletion_jobs_v1',array['integer'],'authenticated',array[]::text[],'authenticated callers cannot claim purge work');
select function_privs_are('public','claim_due_deletion_jobs_v1',array['integer'],'service_role',array['EXECUTE'],'service role can claim purge work');

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.iat',extract(epoch from now())::bigint::text,true);
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.export_family_data_v1('20000000-0000-4000-8000-000000000001','json_v1')$$,
  'owner can export family text and metadata'
);

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.export_family_data_v1('20000000-0000-4000-8000-000000000001','json_v1')$$,
  '42501',null,'editor cannot export family'
);

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select throws_ok(
  $$select public.request_family_deletion_v1('20000000-0000-4000-8000-000000000001')$$,
  '42501',null,'viewer cannot request family deletion'
);

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select throws_ok(
  $$select public.request_account_deletion_v1()$$,
  '23514',null,'sole owner must transfer ownership before account deletion'
);

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select lives_ok(
  $$select public.request_family_deletion_v1('20000000-0000-4000-8000-000000000002')$$,
  'owner can queue complete family deletion'
);
select is(
  (select count(*)::int from public.families where id='20000000-0000-4000-8000-000000000002'),
  0,'queued family becomes inaccessible immediately'
);
select ok(
  (select execute_after>=created_at+interval '30 days' from public.deletion_jobs
    where target_family_id='20000000-0000-4000-8000-000000000002'),
  'family purge is retained for at least 30 days'
);
select lives_ok(
  $$select public.request_account_deletion_v1()$$,
  'account deletion may follow deletion of its sole-owned family'
);

reset role;
select is(
  (select count(*)::int from pg_policies where schemaname='storage' and tablename='objects' and policyname='family_storage_delete'),
  0,'physical storage deletion remains worker-only'
);

select * from finish();
rollback;
