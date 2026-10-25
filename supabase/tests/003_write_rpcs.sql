begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select has_function('public','save_person_v1',array['jsonb'],'atomic person RPC exists');
select has_function('public','save_event_v1',array['jsonb'],'atomic event RPC exists');
select has_function('public','soft_delete_event_v1',array['uuid','uuid','integer'],'event soft-delete RPC exists');
select function_privs_are('public','save_person_v1',array['jsonb'],'authenticated',array['EXECUTE'],'only authenticated can call person RPC');
select function_privs_are('public','save_event_v1',array['jsonb'],'authenticated',array['EXECUTE'],'only authenticated can call event RPC');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('save_person_v1','save_event_v1','soft_delete_event_v1') and p.prosecdef),3,'write RPCs are security definer');

select * from finish();
rollback;
