begin;

create extension if not exists pgtap with schema extensions;

-- Test-only grants are rolled back. They let pgTAP itself keep evaluating while
-- the statements under test run as the real client roles.
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

select plan(88);

-- Required schema and policy contract from the implementation plan.
select has_table('public'::pg_catalog.name, 'cloud_families'::pg_catalog.name);
select has_table(
  'public'::pg_catalog.name,
  'family_memberships'::pg_catalog.name
);
select has_table('public'::pg_catalog.name, 'family_invites'::pg_catalog.name);
select has_function(
  'public'::pg_catalog.name,
  'bootstrap_owner_family'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'create_family_invite'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'preview_family_invite'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'claim_family_invite'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'complete_family_invite'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'revoke_family_invite'::pg_catalog.name
);
select has_function(
  'public'::pg_catalog.name,
  'list_active_family_members'::pg_catalog.name
);
select policies_are(
  'public',
  'family_memberships',
  array['active family roster']
);
select policies_are('public', 'profiles', array['own profile']);

select has_table('public'::pg_catalog.name, 'profiles'::pg_catalog.name);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_class as tables
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = tables.relnamespace
    where schemas.nspname = 'public'
      and tables.relname in (
        'profiles',
        'cloud_families',
        'family_memberships',
        'family_invites'
      )
      and tables.relrowsecurity
  ),
  4,
  'all exposed family tables have row level security enabled'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc as functions
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = functions.pronamespace
    where schemas.nspname = 'public'
      and functions.proname in (
        'bootstrap_owner_family',
        'create_family_invite',
        'preview_family_invite',
        'claim_family_invite',
        'complete_family_invite',
        'revoke_family_invite',
        'list_active_family_members'
      )
      and functions.prosecdef
      and 'search_path=""' = any(functions.proconfig)
  ),
  7,
  'all RPCs are security definer functions with an empty search path'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc as functions
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = functions.pronamespace
    where schemas.nspname = 'private'
      and functions.proname = 'is_active_family_member'
      and functions.prosecdef
      and 'search_path=""' = any(functions.proconfig)
  ),
  1,
  'the private RLS helper is security definer with an empty search path'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('anon'),
        ('authenticated')
    ) as roles(role_name)
    cross join (
      values
        ('profiles'),
        ('cloud_families'),
        ('family_memberships'),
        ('family_invites')
    ) as tables(table_name)
    cross join (
      values
        ('INSERT'),
        ('UPDATE'),
        ('DELETE'),
        ('TRUNCATE')
    ) as privileges(privilege_name)
    where has_table_privilege(
      roles.role_name,
      format('public.%I', tables.table_name),
      privileges.privilege_name
    )
  ),
  'anon and authenticated cannot mutate family tables directly'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.family_memberships',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.family_memberships',
    'SELECT'
  ),
  'membership rows cannot be selected directly by client roles'
);

select ok(
  not exists (
    select 1
    from (
      values
        ('account_id'),
        ('membership_role'),
        ('state'),
        ('joined_at'),
        ('created_at'),
        ('updated_at')
    ) as sensitive(column_name)
    where has_column_privilege(
      'authenticated',
      'public.family_memberships',
      sensitive.column_name,
      'SELECT'
    )
  ),
  'authenticated cannot select account, role, state, or timestamp internals'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as functions
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = functions.pronamespace
    where schemas.nspname = 'public'
      and functions.proname in (
        'bootstrap_owner_family',
        'create_family_invite',
        'preview_family_invite',
        'claim_family_invite',
        'complete_family_invite',
        'revoke_family_invite',
        'list_active_family_members'
      )
      and has_function_privilege('anon', functions.oid, 'EXECUTE')
  ),
  'anon cannot execute family invitation RPCs'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as functions
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = functions.pronamespace
    where schemas.nspname = 'public'
      and functions.proname in (
        'bootstrap_owner_family',
        'create_family_invite',
        'preview_family_invite',
        'claim_family_invite',
        'complete_family_invite',
        'revoke_family_invite',
        'list_active_family_members'
      )
      and exists (
        select 1
        from aclexplode(
          coalesce(
            functions.proacl,
            acldefault('f', functions.proowner)
          )
        ) as privilege
        where privilege.grantee = 0
          and privilege.privilege_type = 'EXECUTE'
      )
  ),
  'PUBLIC cannot execute family invitation RPCs'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc as functions
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = functions.pronamespace
    where schemas.nspname = 'public'
      and functions.proname in (
        'bootstrap_owner_family',
        'create_family_invite',
        'preview_family_invite',
        'claim_family_invite',
        'complete_family_invite',
        'revoke_family_invite',
        'list_active_family_members'
      )
      and has_function_privilege('authenticated', functions.oid, 'EXECUTE')
  ),
  7,
  'authenticated can execute exactly the seven family invitation RPCs'
);

-- Supabase Postgres 17.6.1.106 can crash instead of returning 42501 when a
-- reserved role invokes a function without EXECUTE through pgTAP's dynamic
-- SQL path: https://github.com/supabase/postgres/issues/2112
select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.preview_family_invite(pg_catalog.text)'::pg_catalog.regprocedure,
    'EXECUTE'
  ),
  'anon cannot execute preview_family_invite'
);

set local role authenticated;

select throws_ok(
  $sql$
    select account_id, membership_role, state, joined_at, created_at, updated_at
    from public.family_memberships
  $sql$,
  '42501',
  'permission denied for table family_memberships',
  'authenticated cannot query sensitive membership fields directly'
);

reset role;

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'profiles',
        'cloud_families',
        'family_memberships',
        'family_invites'
      )
      and column_name in (
        'token',
        'recipient_email',
        'wrapping_secret',
        'family_key',
        'member_key',
        'memory_payload',
        'transcript',
        'media_blob'
      )
  ),
  'cloud tables contain no bearer token, plaintext key, or memory-content columns'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'authenticated',
    'authenticated',
    'owner@example.com',
    '',
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'authenticated',
    'authenticated',
    'recipient@example.com',
    '',
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'authenticated',
    'authenticated',
    'outsider@example.com',
    '',
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'authenticated',
    'authenticated',
    'second-recipient@example.com',
    '',
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  );

create or replace function pg_temp.authenticate_as(
  p_account_id uuid,
  p_email text
)
returns void
language plpgsql
as $test_helper$
begin
  perform set_config('request.jwt.claim.sub', p_account_id::text, true);
  perform set_config('request.jwt.claim.email', p_email, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_account_id::text,
      'email', p_email,
      'role', 'authenticated'
    )::text,
    true
  );
end;
$test_helper$;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'the authenticated creator bootstraps an owner family'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_locks as locks
    where locks.pid = pg_catalog.pg_backend_pid()
      and locks.locktype = 'advisory'
      and locks.mode = 'ExclusiveLock'
      and locks.granted
  ),
  'bootstrap holds a transaction-scoped advisory lock after first creation'
);

select is(
  public.bootstrap_owner_family(
    '11111111-1111-4111-8111-111111111111'::uuid,
    'The Keepers',
    '22222222-2222-4222-8222-222222222222'::uuid,
    'Owner',
    'adult',
    'ochre',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
  ),
  public.bootstrap_owner_family(
    '11111111-1111-4111-8111-111111111111'::uuid,
    'The Keepers',
    '22222222-2222-4222-8222-222222222222'::uuid,
    'Owner',
    'adult',
    'ochre',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
  ),
  'owner bootstrap is idempotent for the same account and family'
);

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'familyId',
      'memberId',
      'membershipRole',
      'state'
    ]::text[]
    from pg_catalog.jsonb_object_keys(
      public.bootstrap_owner_family(
        '11111111-1111-4111-8111-111111111111'::uuid,
        'The Keepers',
        '22222222-2222-4222-8222-222222222222'::uuid,
        'Owner',
        'adult',
        'ochre',
        '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
      )
    ) as keys(key)
  )
  and (
    select pg_catalog.bool_and(pg_catalog.jsonb_typeof(value) = 'string')
    from pg_catalog.jsonb_each(
      public.bootstrap_owner_family(
        '11111111-1111-4111-8111-111111111111'::uuid,
        'The Keepers',
        '22222222-2222-4222-8222-222222222222'::uuid,
        'Owner',
        'adult',
        'ochre',
        '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
      )
    )
  ),
  'bootstrap returns only the exact typed result fields'
);

reset role;

create temporary table bootstrap_snapshot as
select pg_catalog.jsonb_build_object(
  'familyName', family.name,
  'profileDisplayName', profile.display_name,
  'memberId', membership.member_id,
  'displayName', membership.display_name,
  'demographicRole', membership.demographic_role,
  'colorToken', membership.color_token,
  'avatarJson', membership.avatar_json,
  'membershipRole', membership.membership_role,
  'state', membership.state
) as result
from public.profiles as profile
join public.family_memberships as membership
  on membership.account_id = profile.account_id
join public.cloud_families as family
  on family.id = membership.family_id
where profile.account_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

set local role authenticated;

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Changed on replay',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'BOOTSTRAP_CONFLICT',
  'bootstrap rejects a replay with a different display name'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'child',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'BOOTSTRAP_CONFLICT',
  'bootstrap rejects a replay with a different demographic role'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'changed',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'BOOTSTRAP_CONFLICT',
  'bootstrap rejects a replay with a different color token'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"changed","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'BOOTSTRAP_CONFLICT',
  'bootstrap rejects a replay with a different avatar'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'Changed family name',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'BOOTSTRAP_CONFLICT',
  'bootstrap rejects a replay with a different family name'
);

reset role;

select is(
  (
    select pg_catalog.jsonb_build_object(
      'familyName', family.name,
      'profileDisplayName', profile.display_name,
      'memberId', membership.member_id,
      'displayName', membership.display_name,
      'demographicRole', membership.demographic_role,
      'colorToken', membership.color_token,
      'avatarJson', membership.avatar_json,
      'membershipRole', membership.membership_role,
      'state', membership.state
    )
    from public.profiles as profile
    join public.family_memberships as membership
      on membership.account_id = profile.account_id
    join public.cloud_families as family
      on family.id = membership.family_id
    where profile.account_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  (select result from bootstrap_snapshot),
  'a rejected bootstrap replay leaves profile and membership unchanged'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      null
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'owner bootstrap rejects a null avatar with the typed profile error'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'bootstrap rejects an empty avatar object'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{"head":"hm1-p-999999"},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'bootstrap rejects an unknown avatar part'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'The Keepers',
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Owner',
      null,
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'owner bootstrap rejects a null demographic role'
);

select throws_ok(
  $sql$
    select public.bootstrap_owner_family(
      '77777777-7777-4777-8777-777777777777'::uuid,
      'Another family',
      '99999999-9999-4999-8999-999999999999'::uuid,
      'Owner',
      'adult',
      'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'DIFFERENT_FAMILY',
  'an account cannot bootstrap a second family'
);

select lives_ok(
  $sql$
    select public.create_family_invite(
      '44444444-4444-4444-8444-444444444444'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      ' Recipient@Example.com ',
      'Yw3NKWbEM2aRElRIu7JbT_QSpJxzLbLIq8G4WBvXEN0',
      '{
        "version": 1,
        "inviteId": "44444444-4444-4444-8444-444444444444",
        "familyId": "11111111-1111-4111-8111-111111111111",
        "nonce": "QEFCQ0RFRkdISUpL",
        "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
        "mac": "lK7nv6RnbkniS7AiGiCIqA"
      }'::jsonb
    )
  $sql$,
  'an active owner creates an encrypted recipient-bound invitation'
);

select throws_ok(
  $sql$
    select public.create_family_invite(
      '43434343-4343-4434-8434-434343434343'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      'recipient@example.com',
      'ZIqlxXn7MPOK90TZfW7IQMepEnekmaDXgPPnMU7KCQs',
      null
    )
  $sql$,
  'P0001',
  'INVALID_ENVELOPE',
  'invite creation rejects a null envelope with the typed envelope error'
);

create temporary table created_result as
select public.create_family_invite(
  '44444444-4444-4444-8444-444444444444'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  'recipient@example.com',
  'Yw3NKWbEM2aRElRIu7JbT_QSpJxzLbLIq8G4WBvXEN0',
  '{
    "version": 1,
    "inviteId": "44444444-4444-4444-8444-444444444444",
    "familyId": "11111111-1111-4111-8111-111111111111",
    "nonce": "QEFCQ0RFRkdISUpL",
    "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
    "mac": "lK7nv6RnbkniS7AiGiCIqA"
  }'::jsonb
) as result;

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'createdAt',
      'expiresAt',
      'familyId',
      'inviteId',
      'state'
    ]::text[]
    from created_result,
      lateral pg_catalog.jsonb_object_keys(result) as keys(key)
  )
  and (
    select pg_catalog.bool_and(pg_catalog.jsonb_typeof(value) = 'string')
    from created_result,
      lateral pg_catalog.jsonb_each(result)
  ),
  'create returns exact string-typed authoritative invitation metadata'
);

reset role;

select ok(
  (
    select expires_at = created_at + interval '24 hours'
    from public.family_invites
    where id = '44444444-4444-4444-8444-444444444444'
  ),
  'the server fixes invitation expiry at exactly 24 hours'
);

select is(
  (
    select token_hash
    from public.family_invites
    where id = '44444444-4444-4444-8444-444444444444'
  ),
  'Yw3NKWbEM2aRElRIu7JbT_QSpJxzLbLIq8G4WBvXEN0',
  'only the canonical SHA-256 token hash is stored'
);

select is(
  (
    select encode(recipient_email_hash, 'hex')
    from public.family_invites
    where id = '44444444-4444-4444-8444-444444444444'
  ),
  '5efba3df1c3be499380cf0c59ceda286171b90abc05cfac25b882fc4368b391c',
  'the normalized recipient email is stored only as its SHA-256 hash'
);

select pg_temp.authenticate_as(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'outsider@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.preview_family_invite(
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001',
  'EMAIL_MISMATCH',
  'preview rejects an authenticated account with the wrong email'
);

reset role;

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'RECIPIENT@example.com'
);

set local role authenticated;

select is(
  public.preview_family_invite(
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
  ) ->> 'familyName',
  'The Keepers',
  'the invited account can preview the family name'
);

select ok(
  not (
    public.preview_family_invite(
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    ) ?| array['envelope', 'nonce', 'ciphertext', 'mac', 'tokenHash']
  ),
  'preview does not expose the encrypted envelope or token hash'
);

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'expiresAt',
      'familyId',
      'familyName',
      'inviteId',
      'ownerName',
      'state'
    ]::text[]
    from pg_catalog.jsonb_object_keys(
      public.preview_family_invite(
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
      )
    ) as keys(key)
  )
  and (
    select pg_catalog.bool_and(pg_catalog.jsonb_typeof(value) = 'string')
    from pg_catalog.jsonb_each(
      public.preview_family_invite(
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
      )
    )
  ),
  'preview returns only the exact typed metadata fields'
);

select lives_ok(
  $sql$
    select public.claim_family_invite(
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      '33333333-3333-4333-8333-333333333333'::uuid,
      'Recipient',
      'adult',
      'plum',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"recipient","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'the invited account claims the invitation once'
);

create temporary table claimed_result as
select public.claim_family_invite(
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  '33333333-3333-4333-8333-333333333333'::uuid,
  'Recipient',
  'adult',
  'plum',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"recipient","selections":{},"colors":{}}'::jsonb
) as result;

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'envelope',
      'familyId',
      'familyName',
      'inviteId',
      'localMemberId',
      'members'
    ]::text[]
    from claimed_result,
      lateral pg_catalog.jsonb_object_keys(result) as keys(key)
  )
  and (
    select pg_catalog.jsonb_typeof(result -> 'envelope') = 'object'
      and pg_catalog.jsonb_typeof(result -> 'members') = 'array'
      and pg_catalog.jsonb_typeof(result -> 'familyId') = 'string'
      and pg_catalog.jsonb_typeof(result -> 'familyName') = 'string'
      and pg_catalog.jsonb_typeof(result -> 'inviteId') = 'string'
      and pg_catalog.jsonb_typeof(result -> 'localMemberId') = 'string'
    from claimed_result
  )
  and (
    select pg_catalog.array_agg(key order by key) = array[
      'ciphertext',
      'familyId',
      'inviteId',
      'mac',
      'nonce',
      'version'
    ]::text[]
    from claimed_result,
      lateral pg_catalog.jsonb_object_keys(result -> 'envelope') as keys(key)
  )
  and (
    select pg_catalog.jsonb_typeof(result -> 'envelope' -> 'version') = 'number'
      and pg_catalog.bool_and(
        case
          when key = 'version' then true
          else pg_catalog.jsonb_typeof(value) = 'string'
        end
      )
    from claimed_result,
      lateral pg_catalog.jsonb_each(result -> 'envelope')
    group by result
  )
  and (
    select pg_catalog.bool_and(
      (
        select pg_catalog.array_agg(key order by key) = array[
          'avatarJson',
          'colorToken',
          'demographicRole',
          'displayName',
          'familyId',
          'joinedAt',
          'memberId'
        ]::text[]
        from pg_catalog.jsonb_object_keys(member) as keys(key)
      )
      and pg_catalog.jsonb_typeof(member -> 'avatarJson') = 'object'
      and pg_catalog.jsonb_typeof(member -> 'colorToken') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'demographicRole') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'displayName') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'familyId') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'joinedAt') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'memberId') = 'string'
    )
    from claimed_result,
      lateral pg_catalog.jsonb_array_elements(result -> 'members')
        as members(member)
  ),
  'claim returns only the exact typed result and envelope fields'
);

select is(
  (select result -> 'envelope' from claimed_result),
  '{
    "version": 1,
    "inviteId": "44444444-4444-4444-8444-444444444444",
    "familyId": "11111111-1111-4111-8111-111111111111",
    "nonce": "QEFCQ0RFRkdISUpL",
    "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
    "mac": "lK7nv6RnbkniS7AiGiCIqA"
  }'::jsonb,
  'claim returns the exact encrypted six-field envelope'
);

select is(
  (select result ->> 'localMemberId' from claimed_result),
  '33333333-3333-4333-8333-333333333333',
  'claim identifies the recipient local member'
);

reset role;

select is(
  (
    select state::text
    from public.family_memberships
    where account_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  'pending_key',
  'claim keeps the new membership pending until local key persistence finishes'
);

set local role authenticated;

select is(
  public.claim_family_invite(
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    'Changed on retry',
    'child',
    'changed',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"changed","selections":{},"colors":{}}'::jsonb
  ),
  (select result from claimed_result),
  'the same claimant receives the same claim result on retry'
);

reset role;

select pg_temp.authenticate_as(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'recipient@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid,
      'Attacker',
      'adult',
      'black',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"attacker","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'ALREADY_CLAIMED',
  'a token cannot be replayed by a different account'
);

reset role;

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recipient@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.complete_family_invite(
      '44444444-4444-4444-8444-444444444444'::uuid
    )
  $sql$,
  'the claimant completes membership after local persistence'
);

create temporary table completed_result as
select public.complete_family_invite(
  '44444444-4444-4444-8444-444444444444'::uuid
) as result;

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'familyId',
      'inviteId',
      'state'
    ]::text[]
    from completed_result,
      lateral pg_catalog.jsonb_object_keys(result) as keys(key)
  )
  and (
    select pg_catalog.bool_and(pg_catalog.jsonb_typeof(value) = 'string')
    from completed_result,
      lateral pg_catalog.jsonb_each(result)
  ),
  'completion returns only the exact string-typed result fields'
);

select is(
  public.complete_family_invite(
    '44444444-4444-4444-8444-444444444444'::uuid
  ),
  (select result from completed_result),
  'completion is idempotent for the same claimant'
);

reset role;

select is(
  (
    select state::text
    from public.family_memberships
    where account_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  'active',
  'completion activates the claimed membership'
);

set local role authenticated;

select is(
  public.claim_family_invite(
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid,
    'Ignored after completion',
    'child',
    'ignored',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"ignored","selections":{},"colors":{}}'::jsonb
  ),
  (select result from claimed_result),
  'the accepted claimant still receives the original idempotent claim result'
);

select throws_ok(
  $sql$
    select public.create_family_invite(
      '99999999-9999-4999-8999-999999999999'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      'other@example.com',
      'Zmh6rfhivXdsj8GLjp-OIAiXFIVu4jOzkCpZHQ1fKSU',
      '{
        "version": 1,
        "inviteId": "99999999-9999-4999-8999-999999999999",
        "familyId": "11111111-1111-4111-8111-111111111111",
        "nonce": "QEFCQ0RFRkdISUpL",
        "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
        "mac": "lK7nv6RnbkniS7AiGiCIqA"
      }'::jsonb
    )
  $sql$,
  'P0001',
  'NOT_OWNER',
  'an active non-owner cannot create invitations'
);

reset role;

select pg_temp.authenticate_as(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'outsider@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.list_active_family_members(
      '11111111-1111-4111-8111-111111111111'::uuid
    )
  $sql$,
  'P0001',
  'FORBIDDEN',
  'a non-member cannot list the family roster'
);

reset role;

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recipient@example.com'
);

set local role authenticated;

create temporary table roster_result as
select public.list_active_family_members(
  '11111111-1111-4111-8111-111111111111'::uuid
) as result;

select is(
  jsonb_array_length(
    (select result from roster_result)
  ),
  2,
  'an active member lists the two active family members'
);

select ok(
  (
    select pg_catalog.bool_and(
      (
        select pg_catalog.array_agg(key order by key) = array[
          'avatarJson',
          'colorToken',
          'demographicRole',
          'displayName',
          'familyId',
          'joinedAt',
          'memberId'
        ]::text[]
        from pg_catalog.jsonb_object_keys(member) as keys(key)
      )
      and pg_catalog.jsonb_typeof(member -> 'avatarJson') = 'object'
      and pg_catalog.jsonb_typeof(member -> 'colorToken') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'demographicRole') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'displayName') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'familyId') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'joinedAt') = 'string'
      and pg_catalog.jsonb_typeof(member -> 'memberId') = 'string'
    )
    from roster_result,
      lateral pg_catalog.jsonb_array_elements(result) as members(member)
  ),
  'roster RPC returns only the exact typed public member projection'
);

select is(
  (select count(*)::integer from public.profiles),
  1,
  'the own-profile RLS policy exposes only the recipient profile'
);

reset role;

insert into public.profiles (account_id, display_name)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Outsider');

select pg_temp.authenticate_as(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'outsider@example.com'
);

set local role authenticated;

select is(
  (select count(*)::integer from public.profiles),
  1,
  'the own-profile RLS policy hides every other account profile'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.create_family_invite(
      '55555555-5555-4555-8555-555555555555'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      'recipient@example.com',
      'Zmh6rfhivXdsj8GLjp-OIAiXFIVu4jOzkCpZHQ1fKSU',
      '{
        "version": 1,
        "inviteId": "55555555-5555-4555-8555-555555555555",
        "familyId": "11111111-1111-4111-8111-111111111111",
        "nonce": "QEFCQ0RFRkdISUpL",
        "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
        "mac": "lK7nv6RnbkniS7AiGiCIqA"
      }'::jsonb
    )
  $sql$,
  'the owner creates a second pending invitation for revocation'
);

reset role;

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recipient@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.revoke_family_invite(
      '55555555-5555-4555-8555-555555555555'::uuid
    )
  $sql$,
  'P0001',
  'NOT_OWNER',
  'an active non-owner cannot revoke an invitation'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.revoke_family_invite(
      '55555555-5555-4555-8555-555555555555'::uuid
    )
  $sql$,
  'the owner revokes a pending invitation'
);

create temporary table revoked_result as
select public.revoke_family_invite(
  '55555555-5555-4555-8555-555555555555'::uuid
) as result;

select ok(
  (
    select pg_catalog.array_agg(key order by key) = array[
      'familyId',
      'inviteId',
      'state'
    ]::text[]
    from revoked_result,
      lateral pg_catalog.jsonb_object_keys(result) as keys(key)
  )
  and (
    select pg_catalog.bool_and(pg_catalog.jsonb_typeof(value) = 'string')
    from revoked_result,
      lateral pg_catalog.jsonb_each(result)
  ),
  'revoke returns only the exact string-typed result fields'
);

select is(
  public.revoke_family_invite(
    '55555555-5555-4555-8555-555555555555'::uuid
  ),
  (select result from revoked_result),
  'owner revocation is idempotent'
);

reset role;

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recipient@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'abababab-abab-4bab-8bab-abababababab'::uuid,
      'Recipient',
      'adult',
      'plum',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"recipient","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVITE_REVOKED',
  'a revoked invitation cannot be claimed'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.create_family_invite(
      '66666666-6666-4666-8666-666666666666'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      'recipient@example.com',
      'cs1uhCLEB_ttCYaQ8RMLfe1-wvf14dML2dUh8BU2N5M',
      '{
        "version": 1,
        "inviteId": "66666666-6666-4666-8666-666666666666",
        "familyId": "11111111-1111-4111-8111-111111111111",
        "nonce": "QEFCQ0RFRkdISUpL",
        "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
        "mac": "lK7nv6RnbkniS7AiGiCIqA"
      }'::jsonb
    )
  $sql$,
  'the owner creates an invitation for the near-boundary expiry test'
);

reset role;

with test_clock as (
  select clock_timestamp() as now
)
update public.family_invites
set
  created_at = test_clock.now - interval '24 hours',
  expires_at = test_clock.now
from test_clock
where id = '66666666-6666-4666-8666-666666666666';

select pg_temp.authenticate_as(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'recipient@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      'bcbcbcbc-bcbc-4bcb-8bcb-bcbcbcbcbcbc'::uuid,
      'Recipient',
      'adult',
      'plum',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"recipient","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVITE_EXPIRED',
  'an unclaimed invitation is rejected just past the 24-hour boundary'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.create_family_invite(
      '78787878-7878-4787-8787-787878787878'::uuid,
      '11111111-1111-4111-8111-111111111111'::uuid,
      'second-recipient@example.com',
      'dYd7tB05O1-4RVzmDs2N2gAdBjFklrFN-n-JVlbuyko',
      '{
        "version": 1,
        "inviteId": "78787878-7878-4787-8787-787878787878",
        "familyId": "11111111-1111-4111-8111-111111111111",
        "nonce": "QEFCQ0RFRkdISUpL",
        "ciphertext": "dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE",
        "mac": "lK7nv6RnbkniS7AiGiCIqA"
      }'::jsonb
    )
  $sql$,
  'the owner creates an invitation that will reach claimed state'
);

reset role;

select pg_temp.authenticate_as(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'second-recipient@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      'adult',
      'sage',
      null
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'claim rejects a null avatar with the typed profile error'
);

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      'adult',
      'sage',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"second","selections":{},"colors":{"skin":"ABCDEF"}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'claim rejects a non-canonical avatar color'
);

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      'adult',
      'sage',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"second","selections":{},"colors":{"unknown":"123456"}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'claim rejects an unknown avatar color slot'
);

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      'adult',
      'sage',
      pg_catalog.jsonb_build_object(
        'schemaVersion', 2,
        'styleId', 'humation-1',
        'styleRevision', 1,
        'seed', pg_catalog.repeat('x', 129),
        'selections', '{}'::jsonb,
        'colors', '{}'::jsonb
      )
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'claim rejects an oversized avatar seed'
);

select throws_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      null,
      'sage',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"second","selections":{},"colors":{}}'::jsonb
    )
  $sql$,
  'P0001',
  'INVALID_PROFILE',
  'claim rejects a null demographic role'
);

select lives_ok(
  $sql$
    select public.claim_family_invite(
      'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI',
      '88888888-8888-4888-8888-888888888888'::uuid,
      'Second recipient',
      'adult',
      'sage',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"second","selections":{},"colors":{"skin":"123456"}}'::jsonb
    )
  $sql$,
  'claim accepts a canonical custom avatar color'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.revoke_family_invite(
      '78787878-7878-4787-8787-787878787878'::uuid
    )
  $sql$,
  'P0001',
  'ALREADY_CLAIMED',
  'a claimed invitation is irreversible and cannot be reported revoked'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.family_memberships
    where account_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ),
  1,
  'a failed claimed-invite revocation preserves the pending membership'
);

select is(
  (
    select state::text
    from public.family_invites
    where id = '78787878-7878-4787-8787-787878787878'
  ),
  'claimed',
  'a failed claimed-invite revocation leaves the invite claimed'
);

select pg_temp.authenticate_as(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'second-recipient@example.com'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.complete_family_invite(
      '78787878-7878-4787-8787-787878787878'::uuid
    )
  $sql$,
  'the claimant can complete after the owner receives ALREADY_CLAIMED'
);

reset role;

select pg_temp.authenticate_as(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'owner@example.com'
);

set local role authenticated;

select throws_ok(
  $sql$
    select public.revoke_family_invite(
      '78787878-7878-4787-8787-787878787878'::uuid
    )
  $sql$,
  'P0001',
  'INVITE_ACCEPTED',
  'an accepted invitation remains non-revocable'
);

reset role;

select * from finish();
rollback;
