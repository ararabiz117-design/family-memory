begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(4);

select has_column('public','places','landmark','place landmark is stored separately');
select has_column('public','places','directions','place directions are stored separately');
select has_function('public','save_place_v1',array['jsonb'],'place write RPC exists');
select function_privs_are(
  'public','save_place_v1',array['jsonb'],'authenticated',array['EXECUTE'],
  'authenticated callers reach role-checked place RPC'
);

select * from finish();
rollback;
