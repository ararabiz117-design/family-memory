begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select is((select count(*)::int from public.people),3,'owner reads own family people');
select lives_ok($$insert into public.people(family_id,display_name) values('20000000-0000-4000-8000-000000000001','架空 追加')$$,'owner can create');
select throws_ok($$insert into public.people(family_id,display_name) values('20000000-0000-4000-8000-000000000002','越境')$$,'42501',null,'owner cannot insert into another family');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select is((select count(*)::int from public.people),4,'viewer reads all own family rows');
select throws_ok($$insert into public.people(family_id,display_name) values('20000000-0000-4000-8000-000000000001','拒否')$$,'42501',null,'viewer cannot insert');
select is((with changed as (update public.people set display_name='拒否' where id='30000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from changed),0,'viewer cannot update');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
select is((select count(*)::int from public.people),0,'other family sees zero people');
select is((select count(*)::int from public.activity_logs),0,'other owner sees zero audit rows');

select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select lives_ok($$update public.people set contact_note='架空メモ' where id='30000000-0000-4000-8000-000000000001'$$,'editor can update');
select is((select version from public.people where id='30000000-0000-4000-8000-000000000001'),2,'version increments');
select throws_ok($$insert into public.person_relationships(family_id,from_person_id,to_person_id,kind) values('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','parent_child')$$,'23514',null,'self relationship rejected');

reset role;
set local role anon;
select throws_ok($$select * from public.people$$,'42501',null,'anon cannot read business tables');
select throws_ok($$insert into public.people(family_id,display_name) values('20000000-0000-4000-8000-000000000001','匿名')$$,'42501',null,'anon cannot insert');

reset role;
select ok((select public=false from storage.buckets where id='family-private'),'storage bucket is private');
select * from finish();
rollback;
