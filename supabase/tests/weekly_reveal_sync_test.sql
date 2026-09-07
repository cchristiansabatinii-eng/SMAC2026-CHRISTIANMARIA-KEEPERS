begin;

create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

select plan(36);

-- Public contract, least privilege, and Realtime wiring.
select has_table(
  'public'::pg_catalog.name,
  'weekly_reveal_entries'::pg_catalog.name
);

select is(
  (
    select pg_catalog.array_agg(column_name::pg_catalog.text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'weekly_reveal_entries'
  ),
  array[
    'id', 'family_id', 'author_member_id', 'created_at', 'format',
    'storage_path', 'blob_sha256', 'blob_bytes', 'state', 'published_at'
  ]::pg_catalog.text[],
  'metadata exposes only encrypted-blob routing and integrity fields'
);

select ok(
  (
    select not bucket.public
      and bucket.file_size_limit = 26214400
      and bucket.allowed_mime_types = array['application/octet-stream']::pg_catalog.text[]
    from storage.buckets as bucket
    where bucket.id = 'keepers-weekly-reveal'
      and bucket.name = 'keepers-weekly-reveal'
  ),
  'Weekly Reveal uses a private 25 MiB ciphertext-only bucket'
);

select ok(
  (
    select table_class.relrowsecurity
    from pg_catalog.pg_class as table_class
    join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = table_class.relnamespace
    where table_schema.nspname = 'public'
      and table_class.relname = 'weekly_reveal_entries'
  ),
  'metadata RLS is enabled'
);

select policies_are(
  'public',
  'weekly_reveal_entries',
  array['active family reads weekly reveal metadata']
);

select is(
  (
    select pg_catalog.count(*)::pg_catalog.int4
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function.pronamespace
    where function_schema.nspname = 'public'
      and function.proname in (
        'publish_weekly_reveal_entry',
        'list_weekly_reveal_entries'
      )
  ),
  2,
  'both Weekly Reveal RPCs exist'
);

select is(
  (
    select pg_catalog.count(*)::pg_catalog.int4
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function.pronamespace
    where function_schema.nspname = 'public'
      and function.proname in (
        'publish_weekly_reveal_entry',
        'list_weekly_reveal_entries'
      )
      and function.prosecdef
      and 'search_path=""' = any(function.proconfig)
  ),
  2,
  'both RPCs are security definer functions with an empty search path'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function.pronamespace
    where function_schema.nspname = 'public'
      and function.proname in (
        'publish_weekly_reveal_entry',
        'list_weekly_reveal_entries'
      )
      and has_function_privilege('anon', function.oid, 'EXECUTE')
  ),
  'anonymous clients cannot execute either RPC'
);

select is(
  (
    select pg_catalog.count(*)::pg_catalog.int4
    from pg_catalog.pg_proc as function
    join pg_catalog.pg_namespace as function_schema
      on function_schema.oid = function.pronamespace
    where function_schema.nspname = 'public'
      and function.proname in (
        'publish_weekly_reveal_entry',
        'list_weekly_reveal_entries'
      )
      and has_function_privilege('authenticated', function.oid, 'EXECUTE')
  ),
  2,
  'authenticated clients can execute both RPCs'
);

select ok(
  has_table_privilege('authenticated', 'public.weekly_reveal_entries', 'SELECT')
  and not has_table_privilege('anon', 'public.weekly_reveal_entries', 'SELECT')
  and not has_table_privilege('authenticated', 'public.weekly_reveal_entries', 'INSERT')
  and not has_table_privilege('authenticated', 'public.weekly_reveal_entries', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.weekly_reveal_entries', 'DELETE'),
  'clients can subscribe to metadata but cannot mutate it directly'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'weekly_reveal_entries'
  ),
  'metadata changes are published to Supabase Realtime'
);

select is(
  (
    select pg_catalog.array_agg(policyname::pg_catalog.text order by policyname)
    from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'weekly reveal:%'
  ),
  array[
    'weekly reveal: active family reads',
    'weekly reveal: author inserts'
  ]::pg_catalog.text[],
  'Storage has family read and create-only author policies'
);

-- Isolated family fixtures.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'authenticated', 'authenticated', 'owner-weekly@example.com', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}', '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'authenticated', 'authenticated', 'relative-weekly@example.com', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}', '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'authenticated', 'authenticated', 'outsider-weekly@example.com', '',
    pg_catalog.clock_timestamp(),
    '{"provider":"email","providers":["email"]}', '{}',
    pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp()
  );

insert into public.cloud_families (id, name, owner_account_id)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'Weekly Family',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (
    '99999999-9999-4999-8999-999999999999',
    'Other Family',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  );

insert into public.family_memberships (
  family_id, account_id, member_id, display_name, demographic_role,
  color_token, avatar_json, membership_role, state, joined_at, created_at,
  updated_at
)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '22222222-2222-4222-8222-222222222222',
    'Owner', 'adult', 'ochre',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}',
    'owner', 'active', '2026-09-01T00:00:00Z',
    '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'
  ),
  (
    '11111111-1111-4111-8111-111111111111',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '44444444-4444-4444-8444-444444444444',
    'Relative', 'adult', 'sage',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"relative","selections":{},"colors":{}}',
    'member', 'active', '2026-09-01T00:00:00Z',
    '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'
  ),
  (
    '99999999-9999-4999-8999-999999999999',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    '88888888-8888-4888-8888-888888888888',
    'Outsider', 'adult', 'berry',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"outsider","selections":{},"colors":{}}',
    'owner', 'active', '2026-09-01T00:00:00Z',
    '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'
  );

create or replace function pg_temp.authenticate_as(p_account_id pg_catalog.uuid)
returns void
language plpgsql
as $test_helper$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_account_id::pg_catalog.text, true);
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object(
      'sub', p_account_id::pg_catalog.text,
      'role', 'authenticated'
    )::pg_catalog.text,
    true
  );
end;
$test_helper$;

select pg_temp.authenticate_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
set local role authenticated;

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '33333333-3333-4333-8333-333333333333',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  'P0001',
  'OBJECT_NOT_FOUND',
  'metadata cannot become visible before its ciphertext upload exists'
);

reset role;

insert into storage.objects (
  bucket_id, name, owner_id, metadata, user_metadata
)
values (
  'keepers-weekly-reveal',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '{"size":3,"mimetype":"application/octet-stream"}',
  '{"sha256":"A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E"}'
);

create temporary table weekly_publish_result (value pg_catalog.jsonb);

set local role authenticated;

insert into weekly_publish_result
select public.publish_weekly_reveal_entry(
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '2026-09-08T08:00:00Z', 'photo',
  '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper',
  'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
);

select is(
  (
    select pg_catalog.array_agg(key order by key collate "C")
    from weekly_publish_result,
      lateral pg_catalog.jsonb_object_keys(value) as keys(key)
  ),
  array[
    'authorId', 'blobBytes', 'blobSha256', 'createdAt', 'entryId',
    'familyId', 'format', 'state', 'storagePath'
  ]::pg_catalog.text[],
  'publish returns only the strict client metadata projection'
);

select is(
  (select value ->> 'state' from weekly_publish_result),
  'pending',
  'new remote reveal entries remain pending ciphertext'
);

select is(
  public.publish_weekly_reveal_entry(
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '2026-09-08T08:00:00Z', 'photo',
    '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper',
    'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
  ),
  (select value from weekly_publish_result),
  'an exact publish retry is idempotent'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from public.weekly_reveal_entries),
  1,
  'an exact retry inserts no duplicate metadata'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '33333333-3333-4333-8333-333333333333',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'voice',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  'P0001',
  'ENTRY_CONFLICT',
  'an entry id cannot be replayed with different metadata'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '44444444-4444-4444-8444-444444444444',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/44444444-4444-4444-8444-444444444444/55555555-5555-4555-8555-555555555555.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  'P0001',
  'FORBIDDEN',
  'an account cannot publish as another active family member'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/not-canonical.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  'P0001',
  'INVALID_REVEAL_ENTRY',
  'publish rejects a noncanonical Storage path'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/55555555-5555-4555-8555-555555555555.keeper',
      'not-a-canonical-sha256', 3
    )
  $sql$,
  'P0001',
  'INVALID_REVEAL_ENTRY',
  'publish rejects a noncanonical SHA-256 digest'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/55555555-5555-4555-8555-555555555555.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 0
    )
  $sql$,
  'P0001',
  'INVALID_REVEAL_ENTRY',
  'publish rejects an empty blob declaration'
);

select throws_ok(
  $sql$
    select public.publish_weekly_reveal_entry(
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'capsule',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/55555555-5555-4555-8555-555555555555.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  'P0001',
  'INVALID_REVEAL_ENTRY',
  'publish rejects a non-reveal format'
);

select is(
  pg_catalog.jsonb_array_length(
    public.list_weekly_reveal_entries(
      '11111111-1111-4111-8111-111111111111'
    )
  ),
  1,
  'the author lists the published entry'
);

select is(
  (
    public.list_weekly_reveal_entries(
      '11111111-1111-4111-8111-111111111111'
    ) -> 0
  ) ->> 'entryId',
  '33333333-3333-4333-8333-333333333333',
  'list uses the strict canonical entry identifier'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from storage.objects),
  1,
  'the author can read their family ciphertext object through Storage RLS'
);

select is(
  (
    with attempted_update as (
      update storage.objects
      set user_metadata = '{"sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}'
      where bucket_id = 'keepers-weekly-reveal'
        and name = '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper'
      returning 1
    )
    select pg_catalog.count(*)::pg_catalog.int4 from attempted_update
  ),
  0,
  'an author cannot overwrite their published ciphertext object'
);

select throws_ok(
  $sql$
    insert into public.weekly_reveal_entries (
      id, family_id, author_member_id, created_at, format, storage_path,
      blob_sha256, blob_bytes
    ) values (
      '55555555-5555-4555-8555-555555555555',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '2026-09-08T08:00:00Z', 'photo',
      '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/55555555-5555-4555-8555-555555555555.keeper',
      'A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E', 3
    )
  $sql$,
  '42501',
  'permission denied for table weekly_reveal_entries',
  'authenticated clients cannot bypass the publish RPC'
);

reset role;

select pg_temp.authenticate_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
set local role authenticated;

select is(
  pg_catalog.jsonb_array_length(
    public.list_weekly_reveal_entries(
      '11111111-1111-4111-8111-111111111111'
    )
  ),
  1,
  'another active family member lists the shared reveal'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from public.weekly_reveal_entries),
  1,
  'metadata RLS lets another active family member subscribe'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from storage.objects),
  1,
  'Storage RLS lets another active family member download ciphertext'
);

select is(
  (
    with attempted_update as (
      update storage.objects
      set user_metadata = '{"sha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}'
      where bucket_id = 'keepers-weekly-reveal'
        and name = '11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/33333333-3333-4333-8333-333333333333.keeper'
      returning 1
    )
    select pg_catalog.count(*)::pg_catalog.int4 from attempted_update
  ),
  0,
  'a relative cannot overwrite another author member ciphertext'
);

reset role;

select pg_temp.authenticate_as('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
set local role authenticated;

select throws_ok(
  $sql$
    select public.list_weekly_reveal_entries(
      '11111111-1111-4111-8111-111111111111'
    )
  $sql$,
  'P0001',
  'FORBIDDEN',
  'an outsider cannot list another family metadata'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from public.weekly_reveal_entries),
  0,
  'metadata RLS hides another family from an outsider'
);

select is(
  (select pg_catalog.count(*)::pg_catalog.int4 from storage.objects),
  0,
  'Storage RLS hides another family ciphertext from an outsider'
);

select throws_ok(
  $sql$
    insert into storage.objects (
      bucket_id, name, owner_id, metadata, user_metadata
    ) values (
      'keepers-weekly-reveal',
      '11111111-1111-4111-8111-111111111111/88888888-8888-4888-8888-888888888888/66666666-6666-4666-8666-666666666666.keeper',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      '{"size":3,"mimetype":"application/octet-stream"}',
      '{"sha256":"A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E"}'
    )
  $sql$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'an outsider cannot upload into another family prefix'
);

reset role;

select * from finish();
rollback;
