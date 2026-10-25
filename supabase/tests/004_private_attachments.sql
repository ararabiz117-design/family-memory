begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(7);

select has_function(
  'public', 'create_attachment_v1', array['jsonb'],
  'attachment registration RPC exists'
);
select has_function(
  'public', 'soft_delete_attachment_v1', array['uuid','uuid','integer'],
  'attachment soft-delete RPC exists'
);
select function_privs_are(
  'public', 'create_attachment_v1', array['jsonb'], 'authenticated',
  array['EXECUTE'], 'only authenticated can register attachment metadata'
);
select function_privs_are(
  'public', 'soft_delete_attachment_v1', array['uuid','uuid','integer'],
  'authenticated', array['EXECUTE'],
  'only authenticated can soft-delete attachment metadata'
);
select is(
  (select public from storage.buckets where id = 'family-private'),
  false, 'attachment bucket remains private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'family-private'),
  5242880::bigint, 'attachment bucket enforces 5MiB'
);
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and cmd in ('UPDATE', 'DELETE')
      and policyname like 'family_storage_%'),
  0, 'clients cannot overwrite or physically delete attachment objects'
);

select * from finish();
rollback;
