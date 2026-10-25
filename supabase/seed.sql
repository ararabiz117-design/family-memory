-- Fictional local-only seed. Never replace with real family data.
-- Local OTP delivery remains the responsibility of Supabase Inbucket.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
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

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
insert into public.people(id,family_id,display_name,kind,show_in_tree,gender,life_status,birth_date,birth_date_precision,living_person_consent_confirmed)
values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','青葉 花','family_relative',true,'female','living','1980-01-01','year',true),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','青葉 樹','family_relative',true,'male','deceased','1948-01-01','year',false),
 ('30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','星野 葵','related_person',false,'unknown','living',null,'unknown',true)
on conflict (id) do nothing;
insert into public.deceased_profiles(family_id,person_id,posthumous_name,religious_form,temple_confirmed)
select '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','清風院（架空）','未確認',false
where not exists(select 1 from public.deceased_profiles where person_id='30000000-0000-4000-8000-000000000002' and deleted_at is null);
select set_config('request.jwt.claim.sub','',true);
