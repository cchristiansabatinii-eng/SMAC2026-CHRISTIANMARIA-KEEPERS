begin;

create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

select plan(107);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as proc
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = proc.pronamespace
    where namespace.nspname in ('public', 'private')
      and proc.proname in (
        'bootstrap_owner_family',
        'create_family_invite',
        'preview_family_invite',
        'claim_family_invite',
        'list_active_family_members',
        'own_family_join_request_json',
        'preview_family_by_code',
        'create_family_join_request',
        'list_pending_family_join_requests'
      )
      and pg_catalog.pg_get_functiondef(proc.oid)
        like '%pg_catalog.coalesce(%'
  ),
  'family routines use valid SQL COALESCE syntax'
);

-- Schema, constraints, RLS, grants, and compatibility.
select has_table(
  'public'::pg_catalog.name,
  'family_join_codes'::pg_catalog.name
);
select has_table(
  'public'::pg_catalog.name,
  'family_join_requests'::pg_catalog.name
);
select has_table(
  'private'::pg_catalog.name,
  'family_code_account_limits'::pg_catalog.name
);

select is(
  (select enum_range(null::public.family_join_request_state)::text),
  '{pending,approved,installed,declined,cancelled,expired}',
  'join-request states are closed and ordered'
);
select is(
  (select enum_range(null::public.family_join_request_cancel_reason)::text),
  '{requester,code_regenerated}',
  'cancel reasons distinguish requester action from code regeneration'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where (n.nspname, c.relname) in (
      ('public', 'family_join_codes'),
      ('public', 'family_join_requests'),
      ('private', 'family_code_account_limits')
    ) and c.relrowsecurity
  ),
  3,
  'all new tables have RLS enabled'
);
select policies_are('public', 'family_join_codes', array['active family code']);
select policies_are(
  'public',
  'family_join_requests',
  array['own or active-family join request']
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid = c.conrelid
    join pg_catalog.pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'family_join_codes'
      and c.contype = 'c'
  ),
  7,
  'family codes enforce hash, version, and canonical envelope checks'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid = c.conrelid
    join pg_catalog.pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'family_join_requests'
      and c.contype = 'c'
  ),
  13,
  'join requests enforce profile, key, expiry, envelope, and state checks'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname in (
        'family_join_requests_account_unresolved_idx',
        'family_join_requests_family_account_unresolved_idx'
      )
      and indexdef like 'CREATE UNIQUE INDEX%'
      and indexdef like '%WHERE (state = ANY%'
  ),
  2,
  'both unresolved-request guards are partial unique indexes'
);
select ok(
  not exists (
    select 1
    from (values ('anon'), ('authenticated')) roles(role_name)
    cross join (values ('family_join_codes'), ('family_join_requests')) tables(table_name)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) privileges(privilege_name)
    where has_table_privilege(
      roles.role_name,
      format('public.%I', tables.table_name),
      privileges.privilege_name
    )
  ),
  'client roles cannot mutate either public backing table'
);
select ok(
  not has_table_privilege('anon', 'private.family_code_account_limits', 'SELECT')
  and not has_table_privilege('authenticated', 'private.family_code_account_limits', 'SELECT')
  and not has_table_privilege('authenticated', 'private.family_code_account_limits', 'INSERT')
  and not has_table_privilege('authenticated', 'private.family_code_account_limits', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.family_code_account_limits', 'DELETE'),
  'client roles have no direct access to durable account-limit state'
);
select is(
  (
    select array_agg(column_name::text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public' and table_name = 'family_join_codes'
  ),
  array[
    'family_id', 'code_version', 'code_hash', 'envelope_version', 'nonce',
    'ciphertext', 'mac', 'creator_account_id', 'created_at', 'updated_at'
  ]::text[],
  'family-code storage has exactly the approved encrypted/hash columns'
);
select is(
  (
    select array_agg(column_name::text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public' and table_name = 'family_join_requests'
  ),
  array[
    'id', 'family_id', 'requester_account_id', 'member_id', 'display_name',
    'demographic_role', 'color_token', 'avatar_json', 'joining_public_key',
    'code_version', 'state', 'decision_account_id',
    'approval_envelope_version', 'approval_ephemeral_public_key',
    'approval_nonce', 'approval_ciphertext', 'approval_mac', 'cancel_reason',
    'created_at', 'expires_at', 'resolved_at', 'updated_at'
  ]::text[],
  'join-request storage has exactly the approved public/encrypted columns'
);
select is(
  (
    select array_agg(column_name::text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'family_code_account_limits'
  ),
  array[
    'account_id', 'window_started_at', 'attempt_count',
    'invalid_attempt_count', 'cooldown_until', 'updated_at'
  ]::text[],
  'private throttle storage contains only account counters and timestamps'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'bootstrap_owner_family_with_code', 'get_family_join_code',
        'preview_family_by_code', 'create_family_join_request',
        'list_pending_family_join_requests', 'get_own_family_join_request',
        'approve_family_join_request', 'decline_family_join_request',
        'cancel_family_join_request', 'complete_family_join_request',
        'regenerate_family_join_code'
      )
      and p.prosecdef
      and 'search_path=""' = any(p.proconfig)
  ),
  11,
  'all eleven family-code RPCs are security definer with an empty search path'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'bootstrap_owner_family_with_code', 'get_family_join_code',
        'preview_family_by_code', 'create_family_join_request',
        'list_pending_family_join_requests', 'get_own_family_join_request',
        'approve_family_join_request', 'decline_family_join_request',
        'cancel_family_join_request', 'complete_family_join_request',
        'regenerate_family_join_code'
      )
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  'anon cannot execute a family-code RPC'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'bootstrap_owner_family_with_code', 'get_family_join_code',
        'preview_family_by_code', 'create_family_join_request',
        'list_pending_family_join_requests', 'get_own_family_join_request',
        'approve_family_join_request', 'decline_family_join_request',
        'cancel_family_join_request', 'complete_family_join_request',
        'regenerate_family_join_code'
      )
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  11,
  'authenticated can execute all eleven family-code RPCs'
);
select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'bootstrap_owner_family', 'create_family_invite',
        'preview_family_invite', 'claim_family_invite',
        'complete_family_invite', 'revoke_family_invite',
        'list_active_family_members'
      )
  ),
  7,
  'all seven legacy invitation RPCs remain present'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in (
        'normalize_family_code', 'is_valid_family_code_envelope',
        'expire_family_join_requests', 'expire_family_join_requests_at',
        'check_family_code_account_limit',
        'record_invalid_family_code_attempt', 'clear_invalid_family_code_attempts',
        'family_join_request_decision_json', 'family_join_code_json',
        'family_member_json', 'pending_family_join_request_json',
        'own_family_join_request_json'
      )
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  'authenticated cannot execute private family-code helpers'
);
select ok(
  has_function_privilege(
    'service_role',
    'private.purge_family_join_requests(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.purge_family_join_requests(timestamptz)',
    'EXECUTE'
  ),
  'purge is service-role-only'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'family_join_requests'
      and trigger.tgname = 'guard_family_join_request_membership'
      and not trigger.tgisinternal
  )
  and exists (
    select 1
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'family_memberships'
      and trigger.tgname = 'guard_family_membership_join_request'
      and not trigger.tgisinternal
  ),
  'membership and join-request inserts share database serialization guards'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  '',
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
from (values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 'owner-a@example.com'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid, 'member-a@example.com'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid, 'owner-b@example.com'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid, 'outsider@example.com'),
  ('10000000-0000-4000-8000-000000000001'::uuid, 'requester-1@example.com'),
  ('10000000-0000-4000-8000-000000000002'::uuid, 'requester-2@example.com'),
  ('10000000-0000-4000-8000-000000000003'::uuid, 'requester-3@example.com'),
  ('10000000-0000-4000-8000-000000000004'::uuid, 'requester-4@example.com'),
  ('10000000-0000-4000-8000-000000000005'::uuid, 'request-quota@example.com'),
  ('10000000-0000-4000-8000-000000000006'::uuid, 'lookup-quota@example.com'),
  ('10000000-0000-4000-8000-000000000007'::uuid, 'regeneration@example.com'),
  ('10000000-0000-4000-8000-000000000008'::uuid, 'already-member@example.com'),
  ('10000000-0000-4000-8000-000000000009'::uuid, 'superseded@example.com'),
  ('10000000-0000-4000-8000-000000000010'::uuid, 'family-quota@example.com')
) fixture(id, email);

create or replace function pg_temp.authenticate_as(p_account_id uuid, p_email text)
returns void
language plpgsql
as $helper$
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
$helper$;

create or replace function pg_temp.execute_sqlstate(p_sql text)
returns text
language plpgsql
as $helper$
begin
  execute p_sql;
  return 'NO_ERROR';
exception when others then
  return sqlstate;
end;
$helper$;

set local role authenticated;
select throws_ok(
  $$select public.get_family_join_code('11111111-1111-4111-8111-111111111111'::uuid)$$,
  'P0001',
  'SIGNED_OUT',
  'an authenticated role without a JWT is rejected'
);
reset role;

select pg_temp.authenticate_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'owner-a@example.com');
set local role authenticated;
select lives_ok(
  $sql$
    select public.bootstrap_owner_family_with_code(
      '11111111-1111-4111-8111-111111111111'::uuid,
      'Family A',
      'aaaaaaaa-1111-4111-8111-111111111111'::uuid,
      'Owner A', 'adult', 'ochre',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner-a","selections":{},"colors":{}}'::jsonb,
      'ABCD2345',
      '{"codecVersion":1,"familyId":"11111111-1111-4111-8111-111111111111","codeVersion":1,"nonce":"AAECAwQFBgcICQoL","ciphertext":"AAECAwQFBgc","mac":"AAECAwQFBgcICQoLDA0ODw"}'::jsonb
    )
  $sql$,
  'creator can bootstrap a family and encrypted join code'
);
create temporary table family_a_code_result as
select public.get_family_join_code(
  '11111111-1111-4111-8111-111111111111'::uuid
) result;
select is(
  (
    select array_agg(key order by key collate "C")
    from family_a_code_result,
      lateral jsonb_object_keys(result) keys(key)
  ),
  array[
    'ciphertext', 'codeVersion', 'codecVersion', 'createdAt',
    'creatorAccountId', 'familyId', 'mac', 'nonce', 'updatedAt'
  ]::text[],
  'code retrieval has the exact success keys'
);
select ok(
  (select result ->> 'familyId' = '11111111-1111-4111-8111-111111111111' from family_a_code_result)
  and (select jsonb_typeof(result -> 'codecVersion') = 'number' from family_a_code_result)
  and (select jsonb_typeof(result -> 'createdAt') = 'string' from family_a_code_result),
  'code retrieval has exact identifier, number, and timestamp types'
);
select is(
  (
    select code_hash
    from public.family_join_codes
    where family_id = '11111111-1111-4111-8111-111111111111'
  ),
  extensions.digest('ABCD2345', 'sha256'),
  'storage persists the family code only as its SHA-256 digest'
);
reset role;

select pg_temp.authenticate_as('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'owner-b@example.com');
set local role authenticated;
select lives_ok(
  $sql$
    select public.bootstrap_owner_family_with_code(
      '22222222-2222-4222-8222-222222222222'::uuid,
      'Family B',
      'cccccccc-2222-4222-8222-222222222222'::uuid,
      'Owner B', 'adult', 'sage',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"owner-b","selections":{},"colors":{}}'::jsonb,
      'BCDE3456',
      '{"codecVersion":1,"familyId":"22222222-2222-4222-8222-222222222222","codeVersion":1,"nonce":"AQIDBAUGBwgJCgsM","ciphertext":"AQIDBAUGBwg","mac":"AQIDBAUGBwgJCgsMDQ4PEA"}'::jsonb
    )
  $sql$,
  'second creator can bootstrap an independent code'
);
reset role;

select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set code_version = 0 where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects a non-positive code version'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set code_hash = decode(repeat('00', 31), 'hex') where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects a hash that is not 32 bytes'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set envelope_version = 2 where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects an unsupported envelope version'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set nonce = 'not-canonical' where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects a noncanonical nonce'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set ciphertext = 'not-canonical' where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects noncanonical ciphertext'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set mac = 'not-canonical' where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects a noncanonical MAC'
);
select is(
  pg_temp.execute_sqlstate($$update public.family_join_codes set updated_at = created_at - interval '1 microsecond' where family_id = '11111111-1111-4111-8111-111111111111'$$),
  '23514',
  'family-code storage rejects timestamps moving backward'
);

insert into public.profiles(account_id, display_name)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Member A');
insert into public.family_memberships(
  family_id, account_id, member_id, display_name, demographic_role,
  color_token, avatar_json, membership_role, state
) values (
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'bbbbbbbb-1111-4111-8111-111111111111',
  'Member A', 'adult', 'plum',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"member-a","selections":{},"colors":{}}',
  'member', 'active'
);

select pg_temp.authenticate_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member-a@example.com');
set local role authenticated;
select is(
  public.get_family_join_code('11111111-1111-4111-8111-111111111111'::uuid) ->> 'familyId',
  '11111111-1111-4111-8111-111111111111',
  'any active family member can retrieve the code envelope'
);
select is(
  (
    select count(*)::integer
    from public.family_join_codes
    where family_id = '11111111-1111-4111-8111-111111111111'
  ),
  1,
  'active-member RLS permits selecting the current family code row'
);
select throws_ok(
  $$select public.get_family_join_code('22222222-2222-4222-8222-222222222222'::uuid)$$,
  'P0001', 'FORBIDDEN',
  'an active member cannot retrieve another family code'
);
reset role;

select pg_temp.authenticate_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'outsider@example.com');
set local role authenticated;
select is((select count(*)::integer from public.family_join_codes), 0, 'RLS hides codes from an unrelated account');
select is((select count(*)::integer from public.family_join_requests), 0, 'RLS hides requests from an unrelated account');
create temporary table preview_result as
select public.preview_family_by_code('ABCD-2345') result;
select is(
  (
    select array_agg(key order by key collate "C")
    from preview_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array['codeVersion', 'familyId', 'familyName', 'members']::text[],
  'preview returns only the exact public family projection'
);
select ok(
  (select jsonb_array_length(result -> 'members') = 2 from preview_result)
  and not (select result::text ~ '(account|email|key|secret)' from preview_result),
  'preview contains the roster but no account or secret material'
);
select ok(
  (
    select bool_and(
      (select count(*) from jsonb_object_keys(member)) = 7
      and member ?& array[
        'avatarJson', 'colorToken', 'demographicRole', 'displayName',
        'familyId', 'joinedAt', 'memberId'
      ]::text[]
    )
    from preview_result,
      lateral jsonb_array_elements(result -> 'members') roster(member)
  ),
  'every preview roster member has the exact public projection'
);
select is(
  public.preview_family_by_code('not-a-code'),
  '{"errorCode":"FAMILY_NOT_FOUND"}'::jsonb,
  'malformed codes use the exact neutral error JSON'
);
reset role;
update private.family_code_account_limits
set cooldown_until = clock_timestamp() + interval '1 hour',
    updated_at = clock_timestamp()
where account_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
select ok(
  (
    select invalid_attempt_count = 1
      and cooldown_until > updated_at
    from private.family_code_account_limits
    where account_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ),
  'a malformed lookup durably records invalid count and cooldown'
);

select pg_temp.authenticate_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'outsider@example.com');
set local role authenticated;
select is(
  public.preview_family_by_code('ABCD2345'),
  '{"errorCode":"FAMILY_NOT_FOUND"}'::jsonb,
  'cooldown does not reveal that a valid family code exists'
);
reset role;
update private.family_code_account_limits
set invalid_attempt_count = 0, cooldown_until = null, updated_at = clock_timestamp()
where account_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

select pg_temp.authenticate_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'outsider@example.com');
set local role authenticated;
select is(
  public.preview_family_by_code('ZZZZ9999'),
  '{"errorCode":"FAMILY_NOT_FOUND"}'::jsonb,
  'unknown well-formed codes use the same exact neutral error JSON'
);
reset role;

select throws_ok(
  $sql$
    with fixture as (select clock_timestamp() created_at)
    insert into public.family_join_requests(
      id, family_id, requester_account_id, member_id, display_name,
      demographic_role, color_token, avatar_json, joining_public_key,
      code_version, state, created_at, expires_at, updated_at
    )
    select
      '60000000-0000-4000-8000-000000000001',
      '11111111-1111-4111-8111-111111111111',
      '10000000-0000-4000-8000-000000000006',
      '60000000-1111-4111-8111-000000000001',
      'Invalid state', 'adult', 'slate',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"state","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      1, 'approved', created_at, created_at + interval '7 days', created_at
    from fixture
  $sql$,
  '23514',
  'new row for relation "family_join_requests" violates check constraint "family_join_requests_state_valid"',
  'state coherence rejects approval without decision and envelope material'
);
select throws_ok(
  $sql$
    with fixture as (select clock_timestamp() created_at)
    insert into public.family_join_requests(
      id, family_id, requester_account_id, member_id, display_name,
      demographic_role, color_token, avatar_json, joining_public_key,
      code_version, created_at, expires_at, updated_at
    )
    select
      '60000000-0000-4000-8000-000000000002',
      '11111111-1111-4111-8111-111111111111',
      '10000000-0000-4000-8000-000000000006',
      '60000000-1111-4111-8111-000000000002',
      'Invalid expiry', 'adult', 'slate',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"expiry","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      1, created_at, created_at + interval '6 days', created_at
    from fixture
  $sql$,
  '23514',
  'new row for relation "family_join_requests" violates check constraint "family_join_requests_expiry_valid"',
  'storage rejects a non-exact seven-day expiry'
);

-- Request creation, replay, RLS, decisions, cancellation, expiry, and install.
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000001', 'requester-1@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '11111111-1111-4111-8111-111111111111', 'ABCD2345',
      '10000000-1111-4111-8111-000000000001', 'Requester One', 'adult', 'blue',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":[],"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001', 'INVALID_JOIN_KEY',
  'request creation rejects malformed avatar JSON'
);
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '11111111-1111-4111-8111-111111111111', 'ABCD2345',
      '10000000-1111-4111-8111-000000000001', 'Requester One', 'adult', 'blue',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}',
      'not-canonical'
    )
  $sql$,
  'P0001', 'INVALID_JOIN_KEY',
  'request creation rejects a noncanonical joining public key'
);
select is(
  public.create_family_join_request(
    '22222222-2222-4222-8222-222222222222', 'ABCD2345',
    '10000000-1111-4111-8111-000000000001', 'Requester One', 'adult', 'blue',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}',
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
  ),
  '{"errorCode":"FAMILY_NOT_FOUND"}'::jsonb,
  'a correct code paired with the wrong family is neutral'
);
reset role;
update private.family_code_account_limits
set invalid_attempt_count = 0, cooldown_until = null, updated_at = clock_timestamp()
where account_id = '10000000-0000-4000-8000-000000000001';

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000001', 'requester-1@example.com');
set local role authenticated;
create temporary table request_one_result as
select public.create_family_join_request(
  '11111111-1111-4111-8111-111111111111', 'ABCD2345',
  '10000000-1111-4111-8111-000000000001', 'Requester One', 'adult', 'blue',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
) result;
select is(
  (
    select array_agg(key order by key collate "C")
    from request_one_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array[
    'approvalEnvelope', 'avatarJson', 'cancelReason', 'codeVersion', 'colorToken',
    'createdAt', 'demographicRole', 'displayName', 'expiresAt',
    'familyId', 'familyName', 'joiningPublicKey', 'memberId',
    'requestId', 'requesterAccountId', 'roster', 'state'
  ]::text[],
  'request creation returns the exact own-request projection'
);
select ok(
  (select result ->> 'state' = 'pending' from request_one_result)
  and (select result -> 'approvalEnvelope' = 'null'::jsonb from request_one_result)
  and (select result -> 'roster' = '[]'::jsonb from request_one_result),
  'a new request has exact pending-state JSON values'
);
select is(
  (
    select expires_at - created_at
    from public.family_join_requests
    where id = (select (result ->> 'requestId')::uuid from request_one_result)
  ),
  interval '7 days',
  'request expiry is exactly seven days'
);
select is(
  public.create_family_join_request(
    '11111111-1111-4111-8111-111111111111', 'ABCD2345',
    '10000000-1111-4111-8111-000000000001', 'Requester One', 'adult', 'blue',
    '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}',
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
  ),
  (select result from request_one_result),
  'an exact unresolved replay is idempotent'
);
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '11111111-1111-4111-8111-111111111111', 'ABCD2345',
      '10000000-1111-4111-8111-000000000099', 'Requester One', 'adult', 'blue',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001', 'REQUEST_ALREADY_PENDING',
  'a conflicting unresolved replay is rejected'
);
select is((select count(*)::integer from public.family_join_requests), 1, 'requester RLS exposes its own request');
select throws_ok(
  $$select public.list_pending_family_join_requests('11111111-1111-4111-8111-111111111111')$$,
  'P0001', 'FORBIDDEN',
  'a requester cannot list a family pending queue'
);
select throws_ok(
  format(
    'select public.approve_family_join_request(%L::uuid, %L::jsonb)',
    (select result ->> 'requestId' from request_one_result),
    '{}'::jsonb
  ),
  'P0001', 'FORBIDDEN',
  'a requester cannot approve its own request'
);
reset role;

select pg_temp.authenticate_as('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'outsider@example.com');
set local role authenticated;
select throws_ok(
  $$select public.list_pending_family_join_requests('11111111-1111-4111-8111-111111111111')$$,
  'P0001', 'FORBIDDEN',
  'an unrelated account cannot list a family pending queue'
);
select is(
  (select count(*)::integer from public.family_join_requests),
  0,
  'unrelated-account RLS hides the existing pending request'
);
select throws_ok(
  format(
    'select public.decline_family_join_request(%L::uuid)',
    (select result ->> 'requestId' from request_one_result)
  ),
  'P0001', 'FORBIDDEN',
  'an unrelated account cannot decline a request'
);
reset role;

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000002', 'requester-2@example.com');
set local role authenticated;
select throws_ok(
  format(
    'select public.cancel_family_join_request(%L::uuid)',
    (select result ->> 'requestId' from request_one_result)
  ),
  'P0001', 'FORBIDDEN',
  'another requester cannot cancel someone else''s request'
);
select throws_ok(
  format(
    'select public.complete_family_join_request(%L::uuid)',
    (select result ->> 'requestId' from request_one_result)
  ),
  'P0001', 'FORBIDDEN',
  'another requester cannot complete someone else''s request'
);
reset role;

select pg_temp.authenticate_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member-a@example.com');
set local role authenticated;
create temporary table pending_list_result as
select public.list_pending_family_join_requests(
  '11111111-1111-4111-8111-111111111111'
) result;
select is(jsonb_array_length((select result from pending_list_result)), 1, 'active member can list the family pending request');
select is(
  (
    select count(*)::integer
    from public.family_join_requests
    where id = (select (result ->> 'requestId')::uuid from request_one_result)
  ),
  1,
  'active-member RLS exposes the existing pending request row'
);
select is(
  (
    select array_agg(key order by key collate "C")
    from pending_list_result,
      lateral jsonb_array_elements(result) item,
      lateral jsonb_object_keys(item) keys(key)
  ),
  array[
    'avatarJson', 'codeVersion', 'colorToken', 'createdAt',
    'demographicRole', 'displayName', 'expiresAt', 'familyId',
    'joiningPublicKey', 'memberId', 'requestId', 'requesterAccountId', 'state'
  ]::text[],
  'pending-list elements have the exact review projection'
);
select throws_ok(
  $sql$
    select public.approve_family_join_request(
      (select (result ->> 'requestId')::uuid from request_one_result),
      jsonb_build_object(
        'version', 1,
        'requestId', (select result ->> 'requestId' from request_one_result),
        'familyId', '11111111-1111-4111-8111-111111111111',
        'requesterAccountId', '10000000-0000-4000-8000-000000000001',
        'codeVersion', 1,
        'ephemeralPublicKey', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        'nonce', 'not-canonical',
        'ciphertext', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        'mac', 'AAECAwQFBgcICQoLDA0ODw'
      )
    )
  $sql$,
  'P0001', 'ENVELOPE_REJECTED',
  'approval rejects noncanonical envelope material'
);
create temporary table approval_result as
select public.approve_family_join_request(
  (select (result ->> 'requestId')::uuid from request_one_result),
  jsonb_build_object(
    'version', 1,
    'requestId', (select result ->> 'requestId' from request_one_result),
    'familyId', '11111111-1111-4111-8111-111111111111',
    'requesterAccountId', '10000000-0000-4000-8000-000000000001',
    'codeVersion', 1,
    'ephemeralPublicKey', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    'nonce', 'AAECAwQFBgcICQoL',
    'ciphertext', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    'mac', 'AAECAwQFBgcICQoLDA0ODw'
  )
) result;
select is(
  (
    select array_agg(key order by key collate "C")
    from approval_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array['familyId', 'requestId', 'state', 'updatedAt']::text[],
  'approval returns the exact decision JSON shape'
);
select is((select result ->> 'state' from approval_result), 'approved', 'any active member can approve');
select is(
  (
    select count(*)::integer
    from public.family_join_requests
    where id = (select (result ->> 'requestId')::uuid from request_one_result)
  ),
  0,
  'active-member RLS hides resolved request and approval material'
);
reset role;

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000001', 'requester-1@example.com');
set local role authenticated;
create temporary table approved_own_result as
select public.get_own_family_join_request() result;
select is(
  (
    select count(*)::integer
    from public.family_join_requests
    where id = (select (result ->> 'requestId')::uuid from request_one_result)
      and state = 'approved'
  ),
  1,
  'requester RLS continues to expose its own resolved request row'
);
select ok(
  (
    select (select count(*) from jsonb_object_keys(result)) = 17
      and result ?& array[
        'approvalEnvelope', 'avatarJson', 'codeVersion', 'colorToken',
        'createdAt', 'demographicRole', 'displayName', 'expiresAt', 'cancelReason',
        'familyId', 'familyName', 'joiningPublicKey', 'memberId',
        'requestId', 'requesterAccountId', 'roster', 'state'
      ]::text[]
      and result -> 'cancelReason' = 'null'::jsonb
    from approved_own_result
  ),
  'approved own request has the exact top-level projection'
);
select ok(
  (
    select (
        select count(*)
        from jsonb_object_keys(result -> 'approvalEnvelope')
      ) = 9
      and (result -> 'approvalEnvelope') ?& array[
        'ciphertext', 'codeVersion', 'ephemeralPublicKey', 'familyId', 'mac',
        'nonce', 'requesterAccountId', 'requestId', 'version'
      ]::text[]
    from approved_own_result
  ),
  'approved own request has the exact approval-envelope projection'
);
select ok(
  (select jsonb_array_length(result -> 'roster') = 3 from approved_own_result)
  and (
    select bool_and(
      (select count(*) from jsonb_object_keys(member)) = 7
      and member ?& array[
        'avatarJson', 'colorToken', 'demographicRole', 'displayName',
        'familyId', 'joinedAt', 'memberId'
      ]::text[]
    )
    from approved_own_result,
      lateral jsonb_array_elements(result -> 'roster') roster(member)
  ),
  'approved own request has only exact roster-member projections'
);
create temporary table install_result as
select public.complete_family_join_request(
  (select (result ->> 'requestId')::uuid from request_one_result)
) result;
select is((select result ->> 'state' from install_result), 'installed', 'requester installs an approved membership');
select is(
  (
    select array_agg(key order by key collate "C")
    from install_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array['familyId', 'requestId', 'state', 'updatedAt']::text[],
  'completion returns the exact decision projection'
);
select is(
  public.complete_family_join_request(
    (select (result ->> 'requestId')::uuid from request_one_result)
  ),
  (select result from install_result),
  'completion replay is idempotent'
);
reset role;
select is(
  (
    select count(*)::integer
    from public.family_memberships
    where account_id = '10000000-0000-4000-8000-000000000001'
  ),
  1,
  'completion creates exactly one family membership'
);

-- Requester cancel and active-member decline.
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000002', 'requester-2@example.com');
set local role authenticated;
create temporary table request_two_result as
select public.create_family_join_request(
  '11111111-1111-4111-8111-111111111111', 'ABCD2345',
  '10000000-1111-4111-8111-000000000002', 'Requester Two', 'child', 'rose',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r2","selections":{},"colors":{}}',
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
) result;
create temporary table cancel_result as
select public.cancel_family_join_request(
  (select (result ->> 'requestId')::uuid from request_two_result)
) result;
select is((select result ->> 'state' from cancel_result), 'cancelled', 'requester can cancel a pending request');
select is(
  (
    select array_agg(key order by key collate "C")
    from cancel_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array['familyId', 'requestId', 'state', 'updatedAt']::text[],
  'cancellation returns the exact decision projection'
);
select is(
  public.cancel_family_join_request(
    (select (result ->> 'requestId')::uuid from request_two_result)
  ),
  (select result from cancel_result),
  'requester cancellation replay returns the authoritative decision'
);
create temporary table cancelled_own_result as
select public.get_own_family_join_request() result;
select is(
  (select result ->> 'cancelReason' from cancelled_own_result),
  'requester',
  'own request identifies an authoritative requester cancellation'
);
reset role;

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000003', 'requester-3@example.com');
set local role authenticated;
create temporary table request_three_result as
select public.create_family_join_request(
  '11111111-1111-4111-8111-111111111111', 'ABCD2345',
  '10000000-1111-4111-8111-000000000003', 'Requester Three', 'adult', 'mint',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r3","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
) result;
reset role;
select pg_temp.authenticate_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member-a@example.com');
set local role authenticated;
create temporary table decline_result as
select public.decline_family_join_request(
  (select (result ->> 'requestId')::uuid from request_three_result)
) result;
select is(
  (select result ->> 'state' from decline_result),
  'declined',
  'an active non-owner member can decline a pending request'
);
select is(
  (
    select array_agg(key order by key collate "C")
    from decline_result, lateral jsonb_object_keys(result) keys(key)
  ),
  array['familyId', 'requestId', 'state', 'updatedAt']::text[],
  'decline returns the exact decision projection'
);
reset role;

-- Exact expiry boundary and purge authority.
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000004', 'requester-4@example.com');
set local role authenticated;
create temporary table request_four_result as
select public.create_family_join_request(
  '11111111-1111-4111-8111-111111111111', 'ABCD2345',
  '10000000-1111-4111-8111-000000000004', 'Requester Four', 'adult', 'gold',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r4","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
) result;
select is(
  public.get_own_family_join_request() ->> 'state',
  'pending',
  'a request strictly before its expiry boundary remains pending'
);
reset role;
create temporary table expiry_boundary as
select clock_timestamp() boundary;
update public.family_join_requests r
set created_at = boundary.boundary - interval '7 days',
    expires_at = boundary.boundary,
    updated_at = boundary.boundary
from expiry_boundary boundary
where r.id = (select (result ->> 'requestId')::uuid from request_four_result);
select is(
  private.expire_family_join_requests_at(
    (select boundary from expiry_boundary)
  ),
  1,
  'expiry includes a row exactly equal to the supplied boundary clock'
);
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000004', 'requester-4@example.com');
set local role authenticated;
select is(
  public.get_own_family_join_request() ->> 'state',
  'expired',
  'a request at its captured exact seven-day boundary expires'
);
select throws_ok(
  format(
    'select public.complete_family_join_request(%L::uuid)',
    (select result ->> 'requestId' from request_four_result)
  ),
  'P0001', 'REQUEST_EXPIRED',
  'an expired request cannot be completed'
);
reset role;

update public.family_join_requests r
set created_at = statement_timestamp() - interval '50 days',
    expires_at = statement_timestamp() - interval '43 days',
    resolved_at = statement_timestamp() - interval '40 days',
    updated_at = statement_timestamp() - interval '40 days'
where r.id = (select (result ->> 'requestId')::uuid from request_two_result);
set local role service_role;
select is(
  private.purge_family_join_requests(clock_timestamp() - interval '30 days'),
  1,
  'service role purges only resolved rows older than the cutoff'
);
reset role;

-- Hourly account/family quotas and lookup quota.
insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, state, cancel_reason, created_at, expires_at,
  resolved_at, updated_at
)
select
  extensions.gen_random_uuid(),
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000005',
  extensions.gen_random_uuid(),
  'Request quota', 'adult', 'slate',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"rq","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  1, 'cancelled', 'requester',
  statement_timestamp() - (n || ' minutes')::interval,
  statement_timestamp() - (n || ' minutes')::interval + interval '7 days',
  statement_timestamp(), statement_timestamp()
from generate_series(1, 10) n;
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000005', 'request-quota@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '11111111-1111-4111-8111-111111111111', 'ABCD2345',
      '10000000-1111-4111-8111-000000000005', 'Request quota', 'adult', 'slate',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"rq","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001', 'RATE_LIMITED',
  'an account cannot create an eleventh request inside one hour'
);
reset role;

insert into private.family_code_account_limits(
  account_id, window_started_at, attempt_count,
  invalid_attempt_count, cooldown_until, updated_at
) values (
  '10000000-0000-4000-8000-000000000006',
  clock_timestamp(), 60, 0, null, clock_timestamp()
);
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000006', 'lookup-quota@example.com');
set local role authenticated;
select throws_ok(
  $$select public.preview_family_by_code('ABCD2345')$$,
  'P0001', 'RATE_LIMITED',
  'the sixty-first lookup inside one hour is rejected'
);
reset role;

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000',
  format('30000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', format('family-quota-%s@example.com', n), '',
  clock_timestamp(), '{"provider":"email","providers":["email"]}', '{}',
  clock_timestamp(), clock_timestamp()
from generate_series(1, 100) n;
insert into public.family_join_requests(
  family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, created_at, expires_at, updated_at
)
select
  '22222222-2222-4222-8222-222222222222',
  format('30000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
  format('30000000-1111-4111-8111-%s', lpad(n::text, 12, '0'))::uuid,
  format('Pending %s', n), 'adult', 'slate',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"fq","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  1, statement_timestamp(), statement_timestamp() + interval '7 days',
  statement_timestamp()
from generate_series(1, 100) n;
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000010', 'family-quota@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '22222222-2222-4222-8222-222222222222', 'BCDE3456',
      '10000000-1111-4111-8111-000000000010', 'Family quota', 'adult', 'slate',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"fq-caller","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001', 'RATE_LIMITED',
  'a family cannot receive a 101st pending request'
);
reset role;

-- One-family uniqueness is enforced at install even for an approved request.
insert into public.profiles(account_id, display_name)
values ('10000000-0000-4000-8000-000000000008', 'Already Member');
insert into public.family_memberships(
  family_id, account_id, member_id, display_name, demographic_role,
  color_token, avatar_json, membership_role, state
) values (
  '22222222-2222-4222-8222-222222222222',
  '10000000-0000-4000-8000-000000000008',
  '10000000-2222-4222-8222-000000000008',
  'Already Member', 'adult', 'blue',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"already","selections":{},"colors":{}}',
  'member', 'pending_key'
);
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000008', 'already-member@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.create_family_join_request(
      '11111111-1111-4111-8111-111111111111', 'ABCD2345',
      '10000000-1111-4111-8111-000000000008', 'Already Member', 'adult', 'blue',
      '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"already","selections":{},"colors":{}}',
      'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
    )
  $sql$,
  'P0001', 'ALREADY_MEMBER',
  'a legacy pending-key membership cannot create a permanent-code request'
);
reset role;

-- Preserve a pre-migration conflicting row to prove completion remains
-- fail-closed if an older deployment already admitted one.
alter table public.family_join_requests
disable trigger guard_family_join_request_membership;
insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, state, decision_account_id, approval_envelope_version,
  approval_ephemeral_public_key, approval_nonce, approval_ciphertext,
  approval_mac, created_at, expires_at, resolved_at, updated_at
) values (
  '88888888-0000-4000-8000-000000000008',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000008',
  '10000000-1111-4111-8111-000000000008',
  'Already Member', 'adult', 'blue',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"already","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  1, 'approved', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1,
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  'AAECAwQFBgcICQoL',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  'AAECAwQFBgcICQoLDA0ODw',
  statement_timestamp(), statement_timestamp() + interval '7 days',
  statement_timestamp(), statement_timestamp()
);
alter table public.family_join_requests
enable trigger guard_family_join_request_membership;
select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000008', 'already-member@example.com');
set local role authenticated;
select throws_ok(
  $$select public.complete_family_join_request('88888888-0000-4000-8000-000000000008')$$,
  'P0001', 'ALREADY_MEMBER',
  'completion cannot install the same account into a second family'
);
reset role;
select ok(
  (select state = 'approved' from public.family_join_requests where id = '88888888-0000-4000-8000-000000000008')
  and (select count(*) = 1 from public.family_memberships where account_id = '10000000-0000-4000-8000-000000000008'),
  'failed second-family completion preserves one membership and the approved request'
);

-- Regeneration is creator-only, collision-safe, and supersedes pending requests neutrally.
insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, created_at, expires_at, updated_at
) values (
  '77777777-0000-4000-8000-000000000007',
  '11111111-1111-4111-8111-111111111111',
  '10000000-0000-4000-8000-000000000009',
  '10000000-1111-4111-8111-000000000007',
  'Regeneration', 'adult', 'violet',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"regen","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  1, statement_timestamp(), statement_timestamp() + interval '7 days',
  statement_timestamp()
);
select pg_temp.authenticate_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member-a@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.regenerate_family_join_code(
      '11111111-1111-4111-8111-111111111111', 1, 'CDEF4567',
      '{"codecVersion":1,"familyId":"11111111-1111-4111-8111-111111111111","codeVersion":2,"nonce":"AgMEBQYHCAkKCwwN","ciphertext":"AgMEBQYHCAk","mac":"AgMEBQYHCAkKCwwNDg8QEQ"}'
    )
  $sql$,
  'P0001', 'NOT_CREATOR',
  'an active non-creator cannot regenerate the code'
);
reset role;
select pg_temp.authenticate_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'owner-a@example.com');
set local role authenticated;
select throws_ok(
  $sql$
    select public.regenerate_family_join_code(
      '11111111-1111-4111-8111-111111111111', 1, 'BCDE3456',
      '{"codecVersion":1,"familyId":"11111111-1111-4111-8111-111111111111","codeVersion":2,"nonce":"AgMEBQYHCAkKCwwN","ciphertext":"AgMEBQYHCAk","mac":"AgMEBQYHCAkKCwwNDg8QEQ"}'
    )
  $sql$,
  'P0001', 'CODE_COLLISION',
  'a code collision is rejected'
);
select ok(
  (select code_version = 1 from public.family_join_codes where family_id = '11111111-1111-4111-8111-111111111111')
  and (select state = 'pending' from public.family_join_requests where id = '77777777-0000-4000-8000-000000000007'),
  'collision rollback preserves both code version and pending request'
);
create temporary table regeneration_result as
select public.regenerate_family_join_code(
  '11111111-1111-4111-8111-111111111111', 1, 'CDEF4567',
  '{"codecVersion":1,"familyId":"11111111-1111-4111-8111-111111111111","codeVersion":2,"nonce":"AgMEBQYHCAkKCwwN","ciphertext":"AgMEBQYHCAk","mac":"AgMEBQYHCAkKCwwNDg8QEQ"}'
) result;
select ok(
  (select result ->> 'codeVersion' = '2' from regeneration_result)
  and (select array_agg(key order by key collate "C") = array[
    'ciphertext', 'codeVersion', 'codecVersion', 'createdAt',
    'creatorAccountId', 'familyId', 'mac', 'nonce', 'updatedAt'
  ]::text[] from regeneration_result, lateral jsonb_object_keys(result) keys(key)),
  'successful regeneration returns the exact code projection at version two'
);
reset role;
select ok(
  (
    select state = 'cancelled'
      and cancel_reason = 'code_regenerated'
    from public.family_join_requests
    where id = '77777777-0000-4000-8000-000000000007'
  ),
  'regeneration cancels pending requests from the superseded version'
);

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000009', 'superseded@example.com');
set local role authenticated;
select is(
  public.get_own_family_join_request() ->> 'cancelReason',
  'code_regenerated',
  'own request identifies authoritative code regeneration after restart'
);
select is(
  public.preview_family_by_code('ABCD2345'),
  '{"errorCode":"FAMILY_NOT_FOUND"}'::jsonb,
  'a superseded code is indistinguishable from malformed and unknown codes'
);
reset role;

select pg_temp.authenticate_as('10000000-0000-4000-8000-000000000007', 'regeneration@example.com');
set local role authenticated;
select is(
  public.preview_family_by_code('CDEF4567') ->> 'familyId',
  '11111111-1111-4111-8111-111111111111',
  'the replacement code resolves after regeneration'
);
reset role;

select * from finish();
rollback;
