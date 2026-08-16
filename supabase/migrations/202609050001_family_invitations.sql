create schema if not exists extensions;
create schema if not exists private;

create extension if not exists pgcrypto with schema extensions;

revoke all on schema private from public, anon, authenticated;

do $migration$
begin
  create type public.family_demographic_role as enum ('adult', 'child');
exception
  when duplicate_object then null;
end;
$migration$;

do $migration$
begin
  create type public.family_membership_role as enum ('owner', 'member');
exception
  when duplicate_object then null;
end;
$migration$;

do $migration$
begin
  create type public.family_membership_state as enum ('pending_key', 'active');
exception
  when duplicate_object then null;
end;
$migration$;

do $migration$
begin
  create type public.family_invite_state as enum (
    'pending',
    'claimed',
    'accepted',
    'revoked'
  );
exception
  when duplicate_object then null;
end;
$migration$;

create or replace function private.is_valid_avatar_json(
  p_avatar pg_catalog.jsonb
)
returns pg_catalog.bool
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_key pg_catalog.text;
  v_value pg_catalog.jsonb;
  v_text pg_catalog.text;
begin
  if p_avatar is null
    or pg_catalog.jsonb_typeof(p_avatar) <> 'object'
    or pg_catalog.octet_length(p_avatar::pg_catalog.text) > 4096
  then
    return false;
  end if;

  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_avatar)) <> 6
    or exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_avatar) as avatar_key(key)
      where avatar_key.key not in (
        'schemaVersion',
        'styleId',
        'styleRevision',
        'seed',
        'selections',
        'colors'
      )
    )
    or pg_catalog.jsonb_typeof(p_avatar -> 'schemaVersion') <> 'number'
    or p_avatar ->> 'schemaVersion' <> '2'
    or pg_catalog.jsonb_typeof(p_avatar -> 'styleId') <> 'string'
    or p_avatar ->> 'styleId' <> 'humation-1'
    or pg_catalog.jsonb_typeof(p_avatar -> 'styleRevision') <> 'number'
    or p_avatar ->> 'styleRevision' <> '1'
    or pg_catalog.jsonb_typeof(p_avatar -> 'seed') <> 'string'
    or pg_catalog.char_length(p_avatar ->> 'seed') not between 1 and 128
    or p_avatar ->> 'seed' <> pg_catalog.btrim(p_avatar ->> 'seed')
    or pg_catalog.jsonb_typeof(p_avatar -> 'selections') <> 'object'
    or pg_catalog.jsonb_typeof(p_avatar -> 'colors') <> 'object'
  then
    return false;
  end if;

  for v_key, v_value in
    select entry.key, entry.value
    from pg_catalog.jsonb_each(p_avatar -> 'selections') as entry(key, value)
  loop
    if pg_catalog.jsonb_typeof(v_value) <> 'string' then
      return false;
    end if;
    v_text := pg_catalog.jsonb_extract_path_text(
      p_avatar -> 'selections',
      v_key
    );
    if not (case v_key
      when 'head' then v_text = any (array[
        'hm1-p-000001', 'hm1-p-000002', 'hm1-p-000003', 'hm1-p-000004',
        'hm1-p-000005', 'hm1-p-000006', 'hm1-p-000007', 'hm1-p-000008',
        'hm1-p-000009', 'hm1-p-000010', 'hm1-p-000011', 'hm1-p-000012',
        'hm1-p-000013', 'hm1-p-000014', 'hm1-p-000015', 'hm1-p-000016',
        'hm1-p-000017', 'hm1-p-000018', 'hm1-p-000019', 'hm1-p-000020',
        'hm1-p-000021', 'hm1-p-000022', 'hm1-p-000023', 'hm1-p-000024'
      ]::pg_catalog.text[])
      when 'body' then v_text = any (array[
        'hm1-p-000025', 'hm1-p-000026', 'hm1-p-000027', 'hm1-p-000028',
        'hm1-p-000029', 'hm1-p-000030', 'hm1-p-000031', 'hm1-p-000032'
      ]::pg_catalog.text[])
      when 'bottom' then v_text = any (array[
        'hm1-p-000033', 'hm1-p-000034', 'hm1-p-000035', 'hm1-p-000036',
        'hm1-p-000037', 'hm1-p-000038', 'hm1-p-000039', 'hm1-p-000040'
      ]::pg_catalog.text[])
      when 'item' then v_text = any (array[
        'hm1-p-000041', 'hm1-p-000042', 'hm1-p-000043', 'hm1-p-000044',
        'hm1-p-000045', 'hm1-p-000046', 'hm1-p-000047', 'hm1-p-000048',
        'hm1-p-000049', 'hm1-p-000050', 'hm1-p-000051', 'hm1-p-000052',
        'hm1-p-000053', 'hm1-p-000054', 'hm1-p-000055', 'hm1-p-000059',
        'hm1-p-000060', 'hm1-p-000061', 'hm1-p-000062', 'hm1-p-000063',
        'hm1-p-000064', 'hm1-p-000065', 'hm1-p-000066', 'hm1-p-000067',
        'hm1-p-000068', 'hm1-p-000069', 'hm1-p-000070', 'hm1-p-000071',
        'hm1-p-000072', 'hm1-p-000073', 'hm1-p-000074', 'hm1-p-000075',
        'hm1-p-000076', 'hm1-p-000077', 'hm1-p-000078', 'hm1-p-000079',
        'hm1-p-000080', 'hm1-p-000081', 'hm1-p-000082', 'hm1-p-000083',
        'hm1-p-000084', 'hm1-p-000085', 'hm1-p-000086'
      ]::pg_catalog.text[])
      when 'glasses' then v_text = any (array[
        'hm1-p-000056', 'hm1-p-000057', 'hm1-p-000058'
      ]::pg_catalog.text[])
      else false
    end) then
      return false;
    end if;
  end loop;

  for v_key, v_value in
    select entry.key, entry.value
    from pg_catalog.jsonb_each(p_avatar -> 'colors') as entry(key, value)
  loop
    if pg_catalog.jsonb_typeof(v_value) <> 'string' then
      return false;
    end if;
    v_text := pg_catalog.jsonb_extract_path_text(p_avatar -> 'colors', v_key);
    if v_key not in ('hair', 'skin', 'clothes', 'bottom')
      or v_text !~ '^[0-9a-f]{6}$'
    then
      return false;
    end if;
  end loop;

  return true;
exception
  when others then return false;
end;
$function$;

revoke all on function private.is_valid_avatar_json(pg_catalog.jsonb)
  from public, anon, authenticated;

create table if not exists public.profiles (
  account_id pg_catalog.uuid primary key references auth.users(id) on delete cascade,
  display_name pg_catalog.text not null,
  created_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  constraint profiles_display_name_valid check (
    display_name = pg_catalog.btrim(display_name)
    and pg_catalog.char_length(display_name) between 1 and 100
  ),
  constraint profiles_timestamps_valid check (updated_at >= created_at)
);

create table if not exists public.cloud_families (
  id pg_catalog.uuid primary key,
  name pg_catalog.text not null,
  owner_account_id pg_catalog.uuid not null unique
    references auth.users(id) on delete restrict,
  created_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  constraint cloud_families_name_valid check (
    name = pg_catalog.btrim(name)
    and pg_catalog.char_length(name) between 1 and 100
  ),
  constraint cloud_families_timestamps_valid check (updated_at >= created_at)
);

create table if not exists public.family_memberships (
  family_id pg_catalog.uuid not null
    references public.cloud_families(id) on delete cascade,
  account_id pg_catalog.uuid not null unique
    references auth.users(id) on delete cascade,
  member_id pg_catalog.uuid not null unique,
  display_name pg_catalog.text not null,
  demographic_role public.family_demographic_role not null,
  color_token pg_catalog.text not null,
  avatar_json pg_catalog.jsonb not null,
  membership_role public.family_membership_role not null,
  state public.family_membership_state not null,
  joined_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  created_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (family_id, account_id),
  unique (family_id, member_id),
  constraint family_memberships_display_name_valid check (
    display_name = pg_catalog.btrim(display_name)
    and pg_catalog.char_length(display_name) between 1 and 100
  ),
  constraint family_memberships_color_token_valid check (
    color_token = pg_catalog.btrim(color_token)
    and pg_catalog.char_length(color_token) between 1 and 64
  ),
  constraint family_memberships_avatar_valid check (
    private.is_valid_avatar_json(avatar_json)
  ),
  constraint family_memberships_timestamps_valid check (
    updated_at >= created_at
    and joined_at >= created_at
  )
);

create table if not exists public.family_invites (
  id pg_catalog.uuid primary key,
  family_id pg_catalog.uuid not null
    references public.cloud_families(id) on delete cascade,
  creator_account_id pg_catalog.uuid not null
    references auth.users(id) on delete restrict,
  recipient_email_hash pg_catalog.bytea not null,
  token_hash pg_catalog.text not null unique,
  version pg_catalog.int2 not null,
  nonce pg_catalog.text not null,
  ciphertext pg_catalog.text not null,
  mac pg_catalog.text not null,
  state public.family_invite_state not null default 'pending',
  claimant_account_id pg_catalog.uuid references auth.users(id) on delete restrict,
  expires_at pg_catalog.timestamptz not null,
  claimed_at pg_catalog.timestamptz,
  accepted_at pg_catalog.timestamptz,
  revoked_at pg_catalog.timestamptz,
  created_at pg_catalog.timestamptz not null,
  updated_at pg_catalog.timestamptz not null,
  constraint family_invites_recipient_hash_valid check (
    pg_catalog.octet_length(recipient_email_hash) = 32
  ),
  constraint family_invites_token_hash_valid check (
    token_hash ~ '^[A-Za-z0-9_-]{43}$'
  ),
  constraint family_invites_version_valid check (version = 1),
  constraint family_invites_nonce_valid check (
    nonce ~ '^[A-Za-z0-9_-]{16}$'
  ),
  constraint family_invites_ciphertext_valid check (
    ciphertext ~ '^[A-Za-z0-9_-]{43}$'
  ),
  constraint family_invites_mac_valid check (
    mac ~ '^[A-Za-z0-9_-]{22}$'
  ),
  constraint family_invites_expiry_valid check (
    expires_at = created_at + '24 hours'::pg_catalog.interval
  ),
  constraint family_invites_timestamps_valid check (updated_at >= created_at),
  constraint family_invites_state_valid check (
    (
      state = 'pending'
      and claimant_account_id is null
      and claimed_at is null
      and accepted_at is null
      and revoked_at is null
    )
    or (
      state = 'claimed'
      and claimant_account_id is not null
      and claimed_at is not null
      and accepted_at is null
      and revoked_at is null
    )
    or (
      state = 'accepted'
      and claimant_account_id is not null
      and claimed_at is not null
      and accepted_at is not null
      and revoked_at is null
    )
    or (
      state = 'revoked'
      and accepted_at is null
      and revoked_at is not null
    )
  )
);

create index if not exists family_memberships_family_state_idx
  on public.family_memberships (family_id, state, joined_at, member_id);

create index if not exists family_invites_family_state_idx
  on public.family_invites (family_id, state, created_at desc);

create index if not exists family_invites_claimant_idx
  on public.family_invites (claimant_account_id)
  where claimant_account_id is not null;

alter table public.profiles enable row level security;
alter table public.cloud_families enable row level security;
alter table public.family_memberships enable row level security;
alter table public.family_invites enable row level security;

create or replace function private.is_active_family_member(p_family_id pg_catalog.uuid)
returns pg_catalog.bool
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from public.family_memberships as membership
      where membership.family_id = p_family_id
        and membership.account_id = auth.uid()
        and membership.state = 'active'
    );
$function$;

revoke execute on function private.is_active_family_member(pg_catalog.uuid)
  from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_active_family_member(pg_catalog.uuid)
  to authenticated;

drop policy if exists "own profile" on public.profiles;
create policy "own profile"
on public.profiles
for select
to authenticated
using (account_id = (select auth.uid()));

drop policy if exists "active family roster" on public.family_memberships;
create policy "active family roster"
on public.family_memberships
for select
to authenticated
using (
  state = 'active'
  and private.is_active_family_member(family_id)
);

revoke all on public.profiles from public, anon, authenticated;
revoke all on public.cloud_families from public, anon, authenticated;
revoke all on public.family_memberships from public, anon, authenticated;
revoke all on public.family_invites from public, anon, authenticated;

grant select on public.profiles to authenticated;

revoke insert, update, delete, truncate on public.profiles, public.cloud_families, public.family_memberships, public.family_invites from anon, authenticated;

create or replace function public.bootstrap_owner_family(
  p_family_id pg_catalog.uuid,
  p_family_name pg_catalog.text,
  p_member_id pg_catalog.uuid,
  p_display_name pg_catalog.text,
  p_demographic_role pg_catalog.text,
  p_color_token pg_catalog.text,
  p_avatar_json pg_catalog.jsonb
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_family public.cloud_families%rowtype;
  v_membership public.family_memberships%rowtype;
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_family_id is null or p_member_id is null then
    raise exception using errcode = 'P0001', message = 'INVALID_IDENTIFIER';
  end if;

  p_family_name := pg_catalog.btrim(pg_catalog.coalesce(p_family_name, ''));
  p_display_name := pg_catalog.btrim(pg_catalog.coalesce(p_display_name, ''));
  p_color_token := pg_catalog.btrim(pg_catalog.coalesce(p_color_token, ''));

  if pg_catalog.char_length(p_family_name) not between 1 and 100
    or pg_catalog.char_length(p_display_name) not between 1 and 100
    or pg_catalog.char_length(p_color_token) not between 1 and 64
    or p_demographic_role is null
    or p_demographic_role not in ('adult', 'child')
    or p_avatar_json is null
    or not private.is_valid_avatar_json(p_avatar_json)
  then
    raise exception using errcode = 'P0001', message = 'INVALID_PROFILE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.bootstrap_owner_family.v1:'::pg_catalog.text
        || v_account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  select membership.*
  into v_membership
  from public.family_memberships as membership
  where membership.account_id = v_account_id
  for update;

  if found then
    if v_membership.family_id <> p_family_id then
      raise exception using errcode = 'P0001', message = 'DIFFERENT_FAMILY';
    end if;

    select family.*
    into v_family
    from public.cloud_families as family
    where family.id = v_membership.family_id
    for update;

    if not found
      or v_family.owner_account_id is distinct from v_account_id
      or v_family.name is distinct from p_family_name
      or v_membership.member_id is distinct from p_member_id
      or v_membership.display_name is distinct from p_display_name
      or v_membership.demographic_role is distinct from
        p_demographic_role::public.family_demographic_role
      or v_membership.color_token is distinct from p_color_token
      or v_membership.avatar_json is distinct from p_avatar_json
      or v_membership.membership_role is distinct from
        'owner'::public.family_membership_role
      or v_membership.state is distinct from
        'active'::public.family_membership_state
    then
      raise exception using errcode = 'P0001', message = 'BOOTSTRAP_CONFLICT';
    end if;

    return pg_catalog.jsonb_build_object(
      'familyId', v_family.id::pg_catalog.text,
      'memberId', v_membership.member_id::pg_catalog.text,
      'membershipRole', v_membership.membership_role::pg_catalog.text,
      'state', v_membership.state::pg_catalog.text
    );
  end if;

  begin
    insert into public.cloud_families (
      id,
      name,
      owner_account_id,
      created_at,
      updated_at
    )
    values (
      p_family_id,
      p_family_name,
      v_account_id,
      v_now,
      v_now
    )
    on conflict (id) do nothing;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'DIFFERENT_FAMILY';
  end;

  select family.*
  into v_family
  from public.cloud_families as family
  where family.id = p_family_id
  for update;

  if not found or v_family.owner_account_id <> v_account_id then
    raise exception using errcode = 'P0001', message = 'FAMILY_CONFLICT';
  end if;

  if v_family.name <> p_family_name then
    raise exception using errcode = 'P0001', message = 'FAMILY_CONFLICT';
  end if;

  insert into public.profiles (
    account_id,
    display_name,
    created_at,
    updated_at
  )
  values (
    v_account_id,
    p_display_name,
    v_now,
    v_now
  )
  on conflict (account_id) do update
  set
    display_name = excluded.display_name,
    updated_at = excluded.updated_at;

  begin
    insert into public.family_memberships (
      family_id,
      account_id,
      member_id,
      display_name,
      demographic_role,
      color_token,
      avatar_json,
      membership_role,
      state,
      joined_at,
      created_at,
      updated_at
    )
    values (
      p_family_id,
      v_account_id,
      p_member_id,
      p_display_name,
      p_demographic_role::public.family_demographic_role,
      p_color_token,
      p_avatar_json,
      'owner',
      'active',
      v_now,
      v_now,
      v_now
    )
    on conflict (family_id, account_id) do nothing;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'MEMBER_CONFLICT';
  end;

  select membership.*
  into v_membership
  from public.family_memberships as membership
  where membership.family_id = p_family_id
    and membership.account_id = v_account_id;

  if not found
    or v_membership.member_id <> p_member_id
    or v_membership.membership_role <> 'owner'
    or v_membership.state <> 'active'
  then
    raise exception using errcode = 'P0001', message = 'MEMBER_CONFLICT';
  end if;

  return pg_catalog.jsonb_build_object(
    'familyId', v_family.id::pg_catalog.text,
    'memberId', v_membership.member_id::pg_catalog.text,
    'membershipRole', v_membership.membership_role::pg_catalog.text,
    'state', v_membership.state::pg_catalog.text
  );
end;
$function$;

create or replace function public.create_family_invite(
  p_invite_id pg_catalog.uuid,
  p_family_id pg_catalog.uuid,
  p_recipient_email pg_catalog.text,
  p_token_hash pg_catalog.text,
  p_envelope pg_catalog.jsonb
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_recipient_email pg_catalog.text;
  v_recipient_email_hash pg_catalog.bytea;
  v_invite public.family_invites%rowtype;
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
  v_nonce pg_catalog.text;
  v_ciphertext pg_catalog.text;
  v_mac pg_catalog.text;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_invite_id is null or p_family_id is null then
    raise exception using errcode = 'P0001', message = 'INVALID_IDENTIFIER';
  end if;

  if not exists (
    select 1
    from public.family_memberships as membership
    join public.cloud_families as family
      on family.id = membership.family_id
    where membership.family_id = p_family_id
      and membership.account_id = v_account_id
      and membership.membership_role = 'owner'
      and membership.state = 'active'
      and family.owner_account_id = v_account_id
  ) then
    raise exception using errcode = 'P0001', message = 'NOT_OWNER';
  end if;

  v_recipient_email := pg_catalog.lower(pg_catalog.btrim(pg_catalog.coalesce(p_recipient_email, '')));
  if pg_catalog.char_length(v_recipient_email) > 254
    or v_recipient_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception using errcode = 'P0001', message = 'INVALID_EMAIL';
  end if;

  v_recipient_email_hash := extensions.digest(v_recipient_email, 'sha256');

  if p_token_hash is null or p_token_hash !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception using errcode = 'P0001', message = 'INVALID_TOKEN_HASH';
  end if;

  begin
    if pg_catalog.octet_length(
      pg_catalog.decode(pg_catalog.translate(p_token_hash, '-_', '+/') || '=', 'base64')
    ) <> 32
      or pg_catalog.rtrim(
        pg_catalog.translate(
          pg_catalog.encode(
            pg_catalog.decode(pg_catalog.translate(p_token_hash, '-_', '+/') || '=', 'base64'),
            'base64'
          ),
          '+/',
          '-_'
        ),
        '='
      ) <> p_token_hash
    then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN_HASH';
    end if;
  exception
    when others then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN_HASH';
  end;

  if p_envelope is null
    or pg_catalog.jsonb_typeof(p_envelope) <> 'object'
    or not (
      p_envelope ?& array[
        'version',
        'inviteId',
        'familyId',
        'nonce',
        'ciphertext',
        'mac'
      ]
    )
    or p_envelope - array['version', 'inviteId', 'familyId', 'nonce', 'ciphertext', 'mac'] <> '{}'::pg_catalog.jsonb
    or pg_catalog.jsonb_typeof(p_envelope -> 'version') <> 'number'
    or pg_catalog.jsonb_typeof(p_envelope -> 'inviteId') <> 'string'
    or pg_catalog.jsonb_typeof(p_envelope -> 'familyId') <> 'string'
    or pg_catalog.jsonb_typeof(p_envelope -> 'nonce') <> 'string'
    or pg_catalog.jsonb_typeof(p_envelope -> 'ciphertext') <> 'string'
    or pg_catalog.jsonb_typeof(p_envelope -> 'mac') <> 'string'
    or p_envelope ->> 'version' <> '1'
    or p_envelope ->> 'inviteId' <> p_invite_id::pg_catalog.text
    or p_envelope ->> 'familyId' <> p_family_id::pg_catalog.text
  then
    raise exception using errcode = 'P0001', message = 'INVALID_ENVELOPE';
  end if;

  v_nonce := p_envelope ->> 'nonce';
  v_ciphertext := p_envelope ->> 'ciphertext';
  v_mac := p_envelope ->> 'mac';

  if v_nonce !~ '^[A-Za-z0-9_-]{16}$'
    or v_ciphertext !~ '^[A-Za-z0-9_-]{43}$'
    or v_mac !~ '^[A-Za-z0-9_-]{22}$'
  then
    raise exception using errcode = 'P0001', message = 'INVALID_ENVELOPE';
  end if;

  begin
    if pg_catalog.octet_length(pg_catalog.decode(pg_catalog.translate(v_nonce, '-_', '+/'), 'base64')) <> 12
      or pg_catalog.octet_length(
        pg_catalog.decode(pg_catalog.translate(v_ciphertext, '-_', '+/') || '=', 'base64')
      ) <> 32
      or pg_catalog.octet_length(
        pg_catalog.decode(pg_catalog.translate(v_mac, '-_', '+/') || '==', 'base64')
      ) <> 16
      or pg_catalog.rtrim(
        pg_catalog.translate(
          pg_catalog.encode(pg_catalog.decode(pg_catalog.translate(v_nonce, '-_', '+/'), 'base64'), 'base64'),
          '+/',
          '-_'
        ),
        '='
      ) <> v_nonce
      or pg_catalog.rtrim(
        pg_catalog.translate(
          pg_catalog.encode(
            pg_catalog.decode(pg_catalog.translate(v_ciphertext, '-_', '+/') || '=', 'base64'),
            'base64'
          ),
          '+/',
          '-_'
        ),
        '='
      ) <> v_ciphertext
      or pg_catalog.rtrim(
        pg_catalog.translate(
          pg_catalog.encode(
            pg_catalog.decode(pg_catalog.translate(v_mac, '-_', '+/') || '==', 'base64'),
            'base64'
          ),
          '+/',
          '-_'
        ),
        '='
      ) <> v_mac
    then
      raise exception using errcode = 'P0001', message = 'INVALID_ENVELOPE';
    end if;
  exception
    when others then
      raise exception using errcode = 'P0001', message = 'INVALID_ENVELOPE';
  end;

  begin
    insert into public.family_invites (
      id,
      family_id,
      creator_account_id,
      recipient_email_hash,
      token_hash,
      version,
      nonce,
      ciphertext,
      mac,
      state,
      expires_at,
      created_at,
      updated_at
    )
    values (
      p_invite_id,
      p_family_id,
      v_account_id,
      v_recipient_email_hash,
      p_token_hash,
      1,
      v_nonce,
      v_ciphertext,
      v_mac,
      'pending',
      v_now + '24 hours'::pg_catalog.interval,
      v_now,
      v_now
    )
    on conflict (id) do nothing;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'INVITE_CONFLICT';
  end;

  select invite.*
  into v_invite
  from public.family_invites as invite
  where invite.id = p_invite_id
  for update;

  if not found
    or v_invite.family_id <> p_family_id
    or v_invite.creator_account_id <> v_account_id
    or v_invite.recipient_email_hash <> v_recipient_email_hash
    or v_invite.token_hash <> p_token_hash
    or v_invite.version <> 1
    or v_invite.nonce <> v_nonce
    or v_invite.ciphertext <> v_ciphertext
    or v_invite.mac <> v_mac
  then
    raise exception using errcode = 'P0001', message = 'INVITE_CONFLICT';
  end if;

  return pg_catalog.jsonb_build_object(
    'inviteId', v_invite.id::pg_catalog.text,
    'familyId', v_invite.family_id::pg_catalog.text,
    'state', v_invite.state::pg_catalog.text,
    'createdAt', v_invite.created_at,
    'expiresAt', v_invite.expires_at
  );
end;
$function$;

create or replace function public.preview_family_invite(p_token pg_catalog.text)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_email pg_catalog.text := pg_catalog.lower(pg_catalog.btrim(pg_catalog.coalesce(auth.jwt() ->> 'email', '')));
  v_token_hash pg_catalog.text;
  v_invite public.family_invites%rowtype;
  v_family_name pg_catalog.text;
  v_owner_name pg_catalog.text;
begin
  if v_account_id is null or v_email = '' then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
  end if;

  begin
    if pg_catalog.rtrim(
      pg_catalog.translate(
        pg_catalog.encode(
          pg_catalog.decode(pg_catalog.translate(p_token, '-_', '+/') || '=', 'base64'),
          'base64'
        ),
        '+/',
        '-_'
      ),
      '='
    ) <> p_token then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
    end if;

    v_token_hash := pg_catalog.rtrim(
      pg_catalog.translate(
        pg_catalog.encode(
          extensions.digest(
            pg_catalog.decode(pg_catalog.translate(p_token, '-_', '+/') || '=', 'base64'),
            'sha256'
          ),
          'base64'
        ),
        '+/',
        '-_'
      ),
      '='
    );
  exception
    when others then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
  end;

  select invite.*
  into v_invite
  from public.family_invites as invite
  where invite.token_hash = v_token_hash;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITE_NOT_FOUND';
  end if;

  if v_invite.recipient_email_hash <> extensions.digest(v_email, 'sha256') then
    raise exception using errcode = 'P0001', message = 'EMAIL_MISMATCH';
  end if;

  if v_invite.state = 'revoked' then
    raise exception using errcode = 'P0001', message = 'INVITE_REVOKED';
  end if;

  if v_invite.state in ('claimed', 'accepted')
    and v_invite.claimant_account_id <> v_account_id
  then
    raise exception using errcode = 'P0001', message = 'ALREADY_CLAIMED';
  end if;

  if v_invite.state = 'pending'
    and pg_catalog.clock_timestamp() >= v_invite.expires_at
  then
    raise exception using errcode = 'P0001', message = 'INVITE_EXPIRED';
  end if;

  select family.name, membership.display_name
  into v_family_name, v_owner_name
  from public.cloud_families as family
  join public.family_memberships as membership
    on membership.family_id = family.id
   and membership.account_id = family.owner_account_id
   and membership.membership_role = 'owner'
   and membership.state = 'active'
  where family.id = v_invite.family_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'FAMILY_UNAVAILABLE';
  end if;

  return pg_catalog.jsonb_build_object(
    'inviteId', v_invite.id::pg_catalog.text,
    'familyId', v_invite.family_id::pg_catalog.text,
    'familyName', v_family_name,
    'ownerName', v_owner_name,
    'expiresAt', v_invite.expires_at,
    'state', v_invite.state::pg_catalog.text
  );
end;
$function$;

create or replace function public.claim_family_invite(
  p_token pg_catalog.text,
  p_member_id pg_catalog.uuid,
  p_display_name pg_catalog.text,
  p_demographic_role pg_catalog.text,
  p_color_token pg_catalog.text,
  p_avatar_json pg_catalog.jsonb
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_email pg_catalog.text := pg_catalog.lower(pg_catalog.btrim(pg_catalog.coalesce(auth.jwt() ->> 'email', '')));
  v_token_hash pg_catalog.text;
  v_invite public.family_invites%rowtype;
  v_existing_family_id pg_catalog.uuid;
  v_family_name pg_catalog.text;
  v_local_member_id pg_catalog.uuid;
  v_roster pg_catalog.jsonb;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null or v_email = '' then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
  end if;

  begin
    if pg_catalog.rtrim(
      pg_catalog.translate(
        pg_catalog.encode(
          pg_catalog.decode(pg_catalog.translate(p_token, '-_', '+/') || '=', 'base64'),
          'base64'
        ),
        '+/',
        '-_'
      ),
      '='
    ) <> p_token then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
    end if;

    v_token_hash := pg_catalog.rtrim(
      pg_catalog.translate(
        pg_catalog.encode(
          extensions.digest(
            pg_catalog.decode(pg_catalog.translate(p_token, '-_', '+/') || '=', 'base64'),
            'sha256'
          ),
          'base64'
        ),
        '+/',
        '-_'
      ),
      '='
    );
  exception
    when others then
      raise exception using errcode = 'P0001', message = 'INVALID_TOKEN';
  end;

  select invite.*
  into v_invite
  from public.family_invites as invite
  where invite.token_hash = v_token_hash
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITE_NOT_FOUND';
  end if;

  if v_invite.recipient_email_hash <> extensions.digest(v_email, 'sha256') then
    raise exception using errcode = 'P0001', message = 'EMAIL_MISMATCH';
  end if;

  if v_invite.state = 'revoked' then
    raise exception using errcode = 'P0001', message = 'INVITE_REVOKED';
  end if;

  if v_invite.state in ('claimed', 'accepted') then
    if v_invite.claimant_account_id <> v_account_id then
      raise exception using errcode = 'P0001', message = 'ALREADY_CLAIMED';
    end if;
  else
    if pg_catalog.clock_timestamp() >= v_invite.expires_at then
      raise exception using errcode = 'P0001', message = 'INVITE_EXPIRED';
    end if;

    p_display_name := pg_catalog.btrim(pg_catalog.coalesce(p_display_name, ''));
    p_color_token := pg_catalog.btrim(pg_catalog.coalesce(p_color_token, ''));
    if p_member_id is null
      or pg_catalog.char_length(p_display_name) not between 1 and 100
      or pg_catalog.char_length(p_color_token) not between 1 and 64
      or p_demographic_role is null
      or p_demographic_role not in ('adult', 'child')
      or p_avatar_json is null
      or not private.is_valid_avatar_json(p_avatar_json)
    then
      raise exception using errcode = 'P0001', message = 'INVALID_PROFILE';
    end if;

    select membership.family_id
    into v_existing_family_id
    from public.family_memberships as membership
    where membership.account_id = v_account_id;

    if found then
      if v_existing_family_id <> v_invite.family_id then
        raise exception using errcode = 'P0001', message = 'DIFFERENT_FAMILY';
      end if;
      raise exception using errcode = 'P0001', message = 'ALREADY_MEMBER';
    end if;

    v_now := pg_catalog.clock_timestamp();

    insert into public.profiles (
      account_id,
      display_name,
      created_at,
      updated_at
    )
    values (
      v_account_id,
      p_display_name,
      v_now,
      v_now
    )
    on conflict (account_id) do update
    set
      display_name = excluded.display_name,
      updated_at = excluded.updated_at;

    begin
      insert into public.family_memberships (
        family_id,
        account_id,
        member_id,
        display_name,
        demographic_role,
        color_token,
        avatar_json,
        membership_role,
        state,
        joined_at,
        created_at,
        updated_at
      )
      values (
        v_invite.family_id,
        v_account_id,
        p_member_id,
        p_display_name,
        p_demographic_role::public.family_demographic_role,
        p_color_token,
        p_avatar_json,
        'member',
        'pending_key',
        v_now,
        v_now,
        v_now
      );
    exception
      when unique_violation then
        raise exception using errcode = 'P0001', message = 'MEMBER_CONFLICT';
    end;

    update public.family_invites
    set
      state = 'claimed',
      claimant_account_id = v_account_id,
      claimed_at = v_now,
      updated_at = v_now
    where id = v_invite.id;

    v_invite.state := 'claimed';
    v_invite.claimant_account_id := v_account_id;
    v_invite.claimed_at := v_now;
    v_invite.updated_at := v_now;
  end if;

  select family.name
  into v_family_name
  from public.cloud_families as family
  where family.id = v_invite.family_id;

  select membership.member_id
  into v_local_member_id
  from public.family_memberships as membership
  where membership.family_id = v_invite.family_id
    and membership.account_id = v_account_id;

  if v_family_name is null or v_local_member_id is null then
    raise exception using errcode = 'P0001', message = 'FAMILY_UNAVAILABLE';
  end if;

  select pg_catalog.coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'memberId', membership.member_id::pg_catalog.text,
        'familyId', membership.family_id::pg_catalog.text,
        'displayName', membership.display_name,
        'demographicRole', membership.demographic_role::pg_catalog.text,
        'colorToken', membership.color_token,
        'avatarJson', membership.avatar_json,
        'joinedAt', membership.joined_at
      )
      order by membership.joined_at, membership.member_id
    ),
    '[]'::pg_catalog.jsonb
  )
  into v_roster
  from public.family_memberships as membership
  where membership.family_id = v_invite.family_id
    and (
      membership.state = 'active'
      or membership.account_id = v_account_id
    );

  return pg_catalog.jsonb_build_object(
    'inviteId', v_invite.id::pg_catalog.text,
    'familyId', v_invite.family_id::pg_catalog.text,
    'familyName', v_family_name,
    'localMemberId', v_local_member_id::pg_catalog.text,
    'envelope', pg_catalog.jsonb_build_object(
      'version', v_invite.version,
      'inviteId', v_invite.id::pg_catalog.text,
      'familyId', v_invite.family_id::pg_catalog.text,
      'nonce', v_invite.nonce,
      'ciphertext', v_invite.ciphertext,
      'mac', v_invite.mac
    ),
    'members', v_roster
  );
end;
$function$;

create or replace function public.complete_family_invite(p_invite_id pg_catalog.uuid)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_invite public.family_invites%rowtype;
  v_now pg_catalog.timestamptz;
  v_updated pg_catalog.int4;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  select invite.*
  into v_invite
  from public.family_invites as invite
  where invite.id = p_invite_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITE_NOT_FOUND';
  end if;

  if v_invite.state = 'revoked' then
    raise exception using errcode = 'P0001', message = 'INVITE_REVOKED';
  end if;

  if v_invite.state = 'pending' then
    raise exception using errcode = 'P0001', message = 'INVITE_NOT_CLAIMED';
  end if;

  if v_invite.claimant_account_id <> v_account_id then
    raise exception using errcode = 'P0001', message = 'ALREADY_CLAIMED';
  end if;

  if v_invite.state = 'claimed' then
    v_now := pg_catalog.clock_timestamp();

    update public.family_memberships
    set
      state = 'active',
      updated_at = v_now
    where family_id = v_invite.family_id
      and account_id = v_account_id
      and state = 'pending_key';

    get diagnostics v_updated = row_count;
    if v_updated <> 1 then
      raise exception using errcode = 'P0001', message = 'MEMBERSHIP_UNAVAILABLE';
    end if;

    update public.family_invites
    set
      state = 'accepted',
      accepted_at = v_now,
      updated_at = v_now
    where id = v_invite.id;
  end if;

  return pg_catalog.jsonb_build_object(
    'inviteId', v_invite.id::pg_catalog.text,
    'familyId', v_invite.family_id::pg_catalog.text,
    'state', 'accepted'
  );
end;
$function$;

create or replace function public.revoke_family_invite(p_invite_id pg_catalog.uuid)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_invite public.family_invites%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  select invite.*
  into v_invite
  from public.family_invites as invite
  where invite.id = p_invite_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITE_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.family_memberships as membership
    join public.cloud_families as family
      on family.id = membership.family_id
    where membership.family_id = v_invite.family_id
      and membership.account_id = v_account_id
      and membership.membership_role = 'owner'
      and membership.state = 'active'
      and family.owner_account_id = v_account_id
  ) then
    raise exception using errcode = 'P0001', message = 'NOT_OWNER';
  end if;

  if v_invite.state = 'claimed' then
    raise exception using errcode = 'P0001', message = 'ALREADY_CLAIMED';
  end if;

  if v_invite.state = 'accepted' then
    raise exception using errcode = 'P0001', message = 'INVITE_ACCEPTED';
  end if;

  if v_invite.state = 'pending' then
    v_now := pg_catalog.clock_timestamp();

    update public.family_invites
    set
      state = 'revoked',
      revoked_at = v_now,
      updated_at = v_now
    where id = v_invite.id
      and state = 'pending';
  end if;

  return pg_catalog.jsonb_build_object(
    'inviteId', v_invite.id::pg_catalog.text,
    'familyId', v_invite.family_id::pg_catalog.text,
    'state', 'revoked'
  );
end;
$function$;

create or replace function public.list_active_family_members(p_family_id pg_catalog.uuid)
returns pg_catalog.jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_roster pg_catalog.jsonb;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if not exists (
    select 1
    from public.family_memberships as membership
    where membership.family_id = p_family_id
      and membership.account_id = v_account_id
      and membership.state = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  select pg_catalog.coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'memberId', membership.member_id::pg_catalog.text,
        'familyId', membership.family_id::pg_catalog.text,
        'displayName', membership.display_name,
        'demographicRole', membership.demographic_role::pg_catalog.text,
        'colorToken', membership.color_token,
        'avatarJson', membership.avatar_json,
        'joinedAt', membership.joined_at
      )
      order by membership.joined_at, membership.member_id
    ),
    '[]'::pg_catalog.jsonb
  )
  into v_roster
  from public.family_memberships as membership
  where membership.family_id = p_family_id
    and membership.state = 'active';

  return v_roster;
end;
$function$;

revoke execute on function public.bootstrap_owner_family(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) from public, anon, authenticated;
grant execute on function public.bootstrap_owner_family(pg_catalog.uuid, pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) to authenticated;

revoke execute on function public.create_family_invite(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) from public, anon, authenticated;
grant execute on function public.create_family_invite(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) to authenticated;

revoke execute on function public.preview_family_invite(pg_catalog.text) from public, anon, authenticated;
grant execute on function public.preview_family_invite(pg_catalog.text) to authenticated;

revoke execute on function public.claim_family_invite(pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) from public, anon, authenticated;
grant execute on function public.claim_family_invite(pg_catalog.text, pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.jsonb) to authenticated;

revoke execute on function public.complete_family_invite(pg_catalog.uuid) from public, anon, authenticated;
grant execute on function public.complete_family_invite(pg_catalog.uuid) to authenticated;

revoke execute on function public.revoke_family_invite(pg_catalog.uuid) from public, anon, authenticated;
grant execute on function public.revoke_family_invite(pg_catalog.uuid) to authenticated;

revoke execute on function public.list_active_family_members(pg_catalog.uuid) from public, anon, authenticated;
grant execute on function public.list_active_family_members(pg_catalog.uuid) to authenticated;
