do $$ begin
  create type public.family_join_request_state as enum
    ('pending', 'approved', 'installed', 'declined', 'cancelled', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.family_join_request_cancel_reason as enum
    ('requester', 'code_regenerated');
exception when duplicate_object then null; end $$;

create or replace function private.is_canonical_base64url(
  p_value pg_catalog.text,
  p_octets pg_catalog.integer
)
returns pg_catalog.boolean
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_padding pg_catalog.text;
  v_decoded pg_catalog.bytea;
begin
  if p_value is null
    or p_octets < 0
    or p_value !~ '^[A-Za-z0-9_-]+$'
    or pg_catalog.char_length(p_value) % 4 = 1
  then
    return false;
  end if;

  v_padding := pg_catalog.repeat(
    '=',
    (4 - pg_catalog.char_length(p_value) % 4) % 4
  );
  v_decoded := pg_catalog.decode(
    pg_catalog.translate(p_value, '-_', '+/') || v_padding,
    'base64'
  );

  return pg_catalog.octet_length(v_decoded) = p_octets
    and pg_catalog.rtrim(
      pg_catalog.translate(
        pg_catalog.encode(v_decoded, 'base64'),
        '+/',
        '-_'
      ),
      '='
    ) = p_value;
exception
  when others then return false;
end;
$function$;

revoke execute on function private.is_canonical_base64url(
  pg_catalog.text,
  pg_catalog.integer
) from public, anon, authenticated;

create table if not exists public.family_join_codes (
  family_id uuid primary key references public.cloud_families(id) on delete cascade,
  code_version integer not null check (code_version > 0),
  code_hash bytea not null unique check (octet_length(code_hash) = 32),
  envelope_version integer not null check (envelope_version = 1),
  nonce text not null,
  ciphertext text not null,
  mac text not null,
  creator_account_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (updated_at >= created_at),
  constraint family_join_codes_nonce_valid check (
    private.is_canonical_base64url(nonce, 12)
  ),
  constraint family_join_codes_ciphertext_valid check (
    private.is_canonical_base64url(ciphertext, 8)
  ),
  constraint family_join_codes_mac_valid check (
    private.is_canonical_base64url(mac, 16)
  )
);

create table if not exists public.family_join_requests (
  id pg_catalog.uuid primary key default extensions.gen_random_uuid(),
  family_id pg_catalog.uuid not null
    references public.cloud_families(id) on delete cascade,
  requester_account_id pg_catalog.uuid not null
    references auth.users(id) on delete cascade,
  member_id pg_catalog.uuid not null,
  display_name pg_catalog.text not null,
  demographic_role public.family_demographic_role not null,
  color_token pg_catalog.text not null,
  avatar_json pg_catalog.jsonb not null,
  joining_public_key pg_catalog.text not null,
  code_version pg_catalog.integer not null,
  state public.family_join_request_state not null default 'pending',
  decision_account_id pg_catalog.uuid
    references auth.users(id) on delete restrict,
  approval_envelope_version pg_catalog.integer,
  approval_ephemeral_public_key pg_catalog.text,
  approval_nonce pg_catalog.text,
  approval_ciphertext pg_catalog.text,
  approval_mac pg_catalog.text,
  cancel_reason public.family_join_request_cancel_reason,
  created_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  expires_at pg_catalog.timestamptz not null,
  resolved_at pg_catalog.timestamptz,
  updated_at pg_catalog.timestamptz not null default pg_catalog.clock_timestamp(),
  constraint family_join_requests_display_name_valid check (
    display_name = pg_catalog.btrim(display_name)
    and pg_catalog.char_length(display_name) between 1 and 100
  ),
  constraint family_join_requests_color_token_valid check (
    color_token = pg_catalog.btrim(color_token)
    and pg_catalog.char_length(color_token) between 1 and 64
  ),
  constraint family_join_requests_avatar_valid check (
    private.is_valid_avatar_json(avatar_json)
  ),
  constraint family_join_requests_joining_public_key_valid check (
    private.is_canonical_base64url(joining_public_key, 32)
  ),
  constraint family_join_requests_code_version_valid check (code_version > 0),
  constraint family_join_requests_expiry_valid check (
    expires_at = created_at + interval '7 days'
  ),
  constraint family_join_requests_timestamps_valid check (
    updated_at >= created_at
    and (resolved_at is null or resolved_at >= created_at)
    and (resolved_at is null or updated_at >= resolved_at)
  ),
  constraint family_join_requests_approval_version_valid check (
    approval_envelope_version is null or approval_envelope_version = 1
  ),
  constraint family_join_requests_approval_public_key_valid check (
    approval_ephemeral_public_key is null
    or private.is_canonical_base64url(approval_ephemeral_public_key, 32)
  ),
  constraint family_join_requests_approval_nonce_valid check (
    approval_nonce is null
    or private.is_canonical_base64url(approval_nonce, 12)
  ),
  constraint family_join_requests_approval_ciphertext_valid check (
    approval_ciphertext is null
    or private.is_canonical_base64url(approval_ciphertext, 32)
  ),
  constraint family_join_requests_approval_mac_valid check (
    approval_mac is null
    or private.is_canonical_base64url(approval_mac, 16)
  ),
  constraint family_join_requests_state_valid check (
    (
      state = 'pending'
      and decision_account_id is null
      and approval_envelope_version is null
      and approval_ephemeral_public_key is null
      and approval_nonce is null
      and approval_ciphertext is null
      and approval_mac is null
      and cancel_reason is null
      and resolved_at is null
    )
    or (
      state in ('approved', 'installed')
      and decision_account_id is not null
      and approval_envelope_version = 1
      and approval_ephemeral_public_key is not null
      and approval_nonce is not null
      and approval_ciphertext is not null
      and approval_mac is not null
      and cancel_reason is null
      and resolved_at is not null
    )
    or (
      state = 'declined'
      and decision_account_id is not null
      and approval_envelope_version is null
      and approval_ephemeral_public_key is null
      and approval_nonce is null
      and approval_ciphertext is null
      and approval_mac is null
      and cancel_reason is null
      and resolved_at is not null
    )
    or (
      state = 'cancelled'
      and decision_account_id is null
      and approval_envelope_version is null
      and approval_ephemeral_public_key is null
      and approval_nonce is null
      and approval_ciphertext is null
      and approval_mac is null
      and cancel_reason is not null
      and resolved_at is not null
    )
    or (
      state = 'expired'
      and decision_account_id is null
      and approval_envelope_version is null
      and approval_ephemeral_public_key is null
      and approval_nonce is null
      and approval_ciphertext is null
      and approval_mac is null
      and cancel_reason is null
      and resolved_at is not null
    )
  )
);

create unique index if not exists family_join_requests_account_unresolved_idx
  on public.family_join_requests (requester_account_id)
  where state in ('pending', 'approved');

create unique index if not exists family_join_requests_family_account_unresolved_idx
  on public.family_join_requests (family_id, requester_account_id)
  where state in ('pending', 'approved');

create index if not exists family_join_requests_family_pending_idx
  on public.family_join_requests (family_id, created_at, id)
  where state = 'pending';

create index if not exists family_join_requests_expiry_pending_idx
  on public.family_join_requests (expires_at, id)
  where state = 'pending';

create index if not exists family_join_requests_requester_updated_idx
  on public.family_join_requests (requester_account_id, updated_at desc, id);

create index if not exists family_join_requests_resolved_idx
  on public.family_join_requests (resolved_at)
  where resolved_at is not null;

create table if not exists private.family_code_account_limits (
  account_id pg_catalog.uuid primary key references auth.users(id) on delete cascade,
  window_started_at pg_catalog.timestamptz not null,
  attempt_count pg_catalog.integer not null check (attempt_count >= 0),
  invalid_attempt_count pg_catalog.integer not null default 0
    check (invalid_attempt_count >= 0),
  cooldown_until pg_catalog.timestamptz,
  updated_at pg_catalog.timestamptz not null,
  constraint family_code_account_limits_timestamps_valid check (
    updated_at >= window_started_at
    and (cooldown_until is null or cooldown_until >= updated_at)
  )
);

alter table private.family_code_account_limits enable row level security;

revoke all on private.family_code_account_limits
  from public, anon, authenticated;

create or replace function private.normalize_family_code(p_code text)
returns text
language plpgsql immutable
set search_path = ''
as $$
declare v_code text := upper(regexp_replace(coalesce(p_code, ''), '[ -]', '', 'g'));
begin
  if v_code !~ '^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{8}$' then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;
  return v_code;
end;
$$;

revoke execute on function private.normalize_family_code(pg_catalog.text)
  from public, anon, authenticated;

create or replace function private.is_valid_family_code_envelope(
  p_envelope pg_catalog.jsonb,
  p_family_id pg_catalog.uuid,
  p_code_version pg_catalog.integer
)
returns pg_catalog.boolean
language plpgsql
immutable
set search_path = ''
as $function$
begin
  return p_envelope is not null
    and pg_catalog.jsonb_typeof(p_envelope) = 'object'
    and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_envelope)) = 6
    and not exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_envelope) as envelope_key(key)
      where envelope_key.key not in (
        'codecVersion', 'familyId', 'codeVersion', 'nonce', 'ciphertext', 'mac'
      )
    )
    and pg_catalog.jsonb_typeof(p_envelope -> 'codecVersion') = 'number'
    and p_envelope ->> 'codecVersion' = '1'
    and pg_catalog.jsonb_typeof(p_envelope -> 'familyId') = 'string'
    and p_envelope ->> 'familyId' = p_family_id::pg_catalog.text
    and pg_catalog.jsonb_typeof(p_envelope -> 'codeVersion') = 'number'
    and p_envelope ->> 'codeVersion' = p_code_version::pg_catalog.text
    and pg_catalog.jsonb_typeof(p_envelope -> 'nonce') = 'string'
    and private.is_canonical_base64url(p_envelope ->> 'nonce', 12)
    and pg_catalog.jsonb_typeof(p_envelope -> 'ciphertext') = 'string'
    and private.is_canonical_base64url(p_envelope ->> 'ciphertext', 8)
    and pg_catalog.jsonb_typeof(p_envelope -> 'mac') = 'string'
    and private.is_canonical_base64url(p_envelope ->> 'mac', 16);
exception
  when others then return false;
end;
$function$;

revoke execute on function private.is_valid_family_code_envelope(
  pg_catalog.jsonb,
  pg_catalog.uuid,
  pg_catalog.integer
) from public, anon, authenticated;

create or replace function private.expire_family_join_requests_at(
  p_now pg_catalog.timestamptz
)
returns pg_catalog.integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count pg_catalog.integer;
begin
  if p_now is null then
    raise exception using errcode = '22004', message = 'NULL_EXPIRY_CLOCK';
  end if;

  update public.family_join_requests
  set
    state = 'expired',
    resolved_at = p_now,
    updated_at = p_now
  where state = 'pending'
    and expires_at <= p_now;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke execute on function private.expire_family_join_requests_at(
  pg_catalog.timestamptz
) from public, anon, authenticated;

create or replace function private.expire_family_join_requests()
returns pg_catalog.integer
language sql
security definer
set search_path = ''
as $function$
  select private.expire_family_join_requests_at(
    pg_catalog.clock_timestamp()
  );
$function$;

revoke execute on function private.expire_family_join_requests()
  from public, anon, authenticated;

create or replace function private.purge_family_join_requests(
  p_before pg_catalog.timestamptz
)
returns pg_catalog.integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count pg_catalog.integer;
begin
  if p_before is null or p_before > pg_catalog.clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'INVALID_RETENTION_CUTOFF';
  end if;

  delete from public.family_join_requests
  where state in ('installed', 'declined', 'cancelled', 'expired')
    and resolved_at < p_before;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke execute on function private.purge_family_join_requests(
  pg_catalog.timestamptz
) from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.purge_family_join_requests(
  pg_catalog.timestamptz
) to service_role;

create or replace function private.check_family_code_account_limit(
  p_account_id pg_catalog.uuid
)
returns pg_catalog.void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limit private.family_code_account_limits%rowtype;
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
begin
  insert into private.family_code_account_limits (
    account_id, window_started_at, attempt_count, updated_at
  ) values (
    p_account_id, v_now, 0, v_now
  )
  on conflict (account_id) do nothing;

  select account_limit.*
  into v_limit
  from private.family_code_account_limits as account_limit
  where account_limit.account_id = p_account_id
  for update;

  if v_limit.window_started_at + interval '1 hour' <= v_now then
    update private.family_code_account_limits
    set
      window_started_at = v_now,
      attempt_count = 1,
      invalid_attempt_count = 0,
      cooldown_until = null,
      updated_at = v_now
    where account_id = p_account_id;
    return;
  end if;

  if v_limit.cooldown_until is not null and v_limit.cooldown_until > v_now then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;

  if v_limit.attempt_count >= 60 then
    raise exception using errcode = 'P0001', message = 'RATE_LIMITED';
  end if;

  update private.family_code_account_limits
  set
    attempt_count = attempt_count + 1,
    cooldown_until = null,
    updated_at = v_now
  where account_id = p_account_id;
end;
$function$;

revoke execute on function private.check_family_code_account_limit(
  pg_catalog.uuid
) from public, anon, authenticated;

create or replace function private.record_invalid_family_code_attempt(
  p_account_id pg_catalog.uuid
)
returns pg_catalog.void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
begin
  update private.family_code_account_limits
  set
    invalid_attempt_count = invalid_attempt_count + 1,
    cooldown_until = v_now + pg_catalog.make_interval(
      secs => pg_catalog.least(
        300::pg_catalog.numeric,
        pg_catalog.power(2::pg_catalog.numeric, invalid_attempt_count)
      )::pg_catalog.integer
    ),
    updated_at = v_now
  where account_id = p_account_id;
end;
$function$;

revoke execute on function private.record_invalid_family_code_attempt(
  pg_catalog.uuid
) from public, anon, authenticated;

create or replace function private.clear_invalid_family_code_attempts(
  p_account_id pg_catalog.uuid
)
returns pg_catalog.void
language sql
security definer
set search_path = ''
as $function$
  update private.family_code_account_limits
  set
    invalid_attempt_count = 0,
    cooldown_until = null,
    updated_at = pg_catalog.clock_timestamp()
  where account_id = p_account_id;
$function$;

revoke execute on function private.clear_invalid_family_code_attempts(
  pg_catalog.uuid
) from public, anon, authenticated;

create or replace function private.family_join_request_decision_json(
  p_request public.family_join_requests
)
returns pg_catalog.jsonb
language sql
stable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'requestId', p_request.id::pg_catalog.text,
    'familyId', p_request.family_id::pg_catalog.text,
    'state', p_request.state::pg_catalog.text,
    'updatedAt', p_request.updated_at
  );
$function$;

revoke execute on function private.family_join_request_decision_json(
  public.family_join_requests
) from public, anon, authenticated;

create or replace function private.family_join_code_json(
  p_code public.family_join_codes
)
returns pg_catalog.jsonb
language sql
stable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'codecVersion', p_code.envelope_version,
    'familyId', p_code.family_id::pg_catalog.text,
    'codeVersion', p_code.code_version,
    'nonce', p_code.nonce,
    'ciphertext', p_code.ciphertext,
    'mac', p_code.mac,
    'creatorAccountId', p_code.creator_account_id::pg_catalog.text,
    'createdAt', p_code.created_at,
    'updatedAt', p_code.updated_at
  );
$function$;

revoke execute on function private.family_join_code_json(
  public.family_join_codes
) from public, anon, authenticated;

create or replace function private.family_member_json(
  p_membership public.family_memberships
)
returns pg_catalog.jsonb
language sql
stable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'memberId', p_membership.member_id::pg_catalog.text,
    'familyId', p_membership.family_id::pg_catalog.text,
    'displayName', p_membership.display_name,
    'demographicRole', p_membership.demographic_role::pg_catalog.text,
    'colorToken', p_membership.color_token,
    'avatarJson', p_membership.avatar_json,
    'joinedAt', p_membership.joined_at
  );
$function$;

revoke execute on function private.family_member_json(
  public.family_memberships
) from public, anon, authenticated;

create or replace function private.pending_family_join_request_json(
  p_request public.family_join_requests
)
returns pg_catalog.jsonb
language sql
stable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'requestId', p_request.id::pg_catalog.text,
    'familyId', p_request.family_id::pg_catalog.text,
    'requesterAccountId', p_request.requester_account_id::pg_catalog.text,
    'memberId', p_request.member_id::pg_catalog.text,
    'displayName', p_request.display_name,
    'demographicRole', p_request.demographic_role::pg_catalog.text,
    'colorToken', p_request.color_token,
    'avatarJson', p_request.avatar_json,
    'joiningPublicKey', p_request.joining_public_key,
    'codeVersion', p_request.code_version,
    'state', p_request.state::pg_catalog.text,
    'createdAt', p_request.created_at,
    'expiresAt', p_request.expires_at
  );
$function$;

revoke execute on function private.pending_family_join_request_json(
  public.family_join_requests
) from public, anon, authenticated;

create or replace function private.own_family_join_request_json(
  p_request public.family_join_requests
)
returns pg_catalog.jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_family_name pg_catalog.text;
  v_envelope pg_catalog.jsonb := 'null'::pg_catalog.jsonb;
  v_roster pg_catalog.jsonb := '[]'::pg_catalog.jsonb;
begin
  select family.name
  into v_family_name
  from public.cloud_families as family
  where family.id = p_request.family_id;

  if v_family_name is null then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;

  if p_request.state in ('approved', 'installed') then
    v_envelope := pg_catalog.jsonb_build_object(
      'version', p_request.approval_envelope_version,
      'requestId', p_request.id::pg_catalog.text,
      'familyId', p_request.family_id::pg_catalog.text,
      'requesterAccountId', p_request.requester_account_id::pg_catalog.text,
      'codeVersion', p_request.code_version,
      'ephemeralPublicKey', p_request.approval_ephemeral_public_key,
      'nonce', p_request.approval_nonce,
      'ciphertext', p_request.approval_ciphertext,
      'mac', p_request.approval_mac
    );

    select pg_catalog.coalesce(
      pg_catalog.jsonb_agg(roster.member_json order by roster.joined_at, roster.member_id),
      '[]'::pg_catalog.jsonb
    )
    into v_roster
    from (
      select
        membership.joined_at,
        membership.member_id,
        private.family_member_json(membership) as member_json
      from public.family_memberships as membership
      where membership.family_id = p_request.family_id
        and membership.state = 'active'
      union all
      select
        p_request.created_at,
        p_request.member_id,
        pg_catalog.jsonb_build_object(
          'memberId', p_request.member_id::pg_catalog.text,
          'familyId', p_request.family_id::pg_catalog.text,
          'displayName', p_request.display_name,
          'demographicRole', p_request.demographic_role::pg_catalog.text,
          'colorToken', p_request.color_token,
          'avatarJson', p_request.avatar_json,
          'joinedAt', p_request.created_at
        )
      where p_request.state = 'approved'
    ) as roster(joined_at, member_id, member_json);
  end if;

  return private.pending_family_join_request_json(p_request)
    || pg_catalog.jsonb_build_object(
      'familyName', v_family_name,
      'approvalEnvelope', v_envelope,
      'roster', v_roster
    );
end;
$function$;

revoke execute on function private.own_family_join_request_json(
  public.family_join_requests
) from public, anon, authenticated;

alter table public.family_join_codes enable row level security;
alter table public.family_join_requests enable row level security;

drop policy if exists "active family code" on public.family_join_codes;
create policy "active family code"
on public.family_join_codes
for select
to authenticated
using (private.is_active_family_member(family_id));

drop policy if exists "own or active-family join request"
  on public.family_join_requests;
create policy "own or active-family join request"
on public.family_join_requests
for select
to authenticated
using (
  requester_account_id = (select auth.uid())
  or (
    state = 'pending'
    and private.is_active_family_member(family_id)
  )
);

revoke all on public.family_join_codes from public, anon, authenticated;
revoke all on public.family_join_requests from public, anon, authenticated;
grant select on public.family_join_codes to authenticated;
grant select on public.family_join_requests to authenticated;
revoke insert, update, delete, truncate
  on public.family_join_codes, public.family_join_requests
  from anon, authenticated;

do $publication$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'family_join_requests'
  ) then
    alter publication supabase_realtime
      add table public.family_join_requests;
  end if;
end;
$publication$;

create or replace function public.get_family_join_code(
  p_family_id pg_catalog.uuid
)
returns pg_catalog.jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_code public.family_join_codes%rowtype;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_family_id is null
    or not private.is_active_family_member(p_family_id)
  then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  select code.*
  into v_code
  from public.family_join_codes as code
  where code.family_id = p_family_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;

  return private.family_join_code_json(v_code);
end;
$function$;

create or replace function public.bootstrap_owner_family_with_code(
  p_family_id uuid,
  p_family_name text,
  p_member_id uuid,
  p_display_name text,
  p_demographic_role text,
  p_color_token text,
  p_avatar_json jsonb,
  p_code text,
  p_code_envelope jsonb
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_account_id uuid := auth.uid();
  v_code text;
  v_existing public.family_join_codes%rowtype;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  v_code := private.normalize_family_code(p_code);
  perform public.bootstrap_owner_family(
    p_family_id, p_family_name, p_member_id, p_display_name,
    p_demographic_role, p_color_token, p_avatar_json
  );

  select code.*
  into v_existing
  from public.family_join_codes as code
  where code.family_id = p_family_id
  for update;

  if found then
    return private.family_join_code_json(v_existing);
  end if;

  if not private.is_valid_family_code_envelope(
    p_code_envelope,
    p_family_id,
    1
  ) then
    raise exception using errcode = 'P0001', message = 'ENVELOPE_REJECTED';
  end if;

  begin
    insert into public.family_join_codes (
      family_id, code_version, code_hash, envelope_version,
      nonce, ciphertext, mac, creator_account_id
    ) values (
      p_family_id, 1, extensions.digest(v_code, 'sha256'),
      (p_code_envelope->>'codecVersion')::integer,
      p_code_envelope->>'nonce', p_code_envelope->>'ciphertext',
      p_code_envelope->>'mac', v_account_id
    ) on conflict (family_id) do nothing;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'CODE_COLLISION';
  end;
  return public.get_family_join_code(p_family_id);
end;
$$;

create or replace function public.preview_family_by_code(
  p_code pg_catalog.text
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_code pg_catalog.text;
  v_family_code public.family_join_codes%rowtype;
  v_family_name pg_catalog.text;
  v_members pg_catalog.jsonb;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.family_code_lookup.v1:'::pg_catalog.text
        || v_account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );
  begin
    perform private.check_family_code_account_limit(v_account_id);
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'FAMILY_NOT_FOUND' then
        return pg_catalog.jsonb_build_object(
          'errorCode',
          'FAMILY_NOT_FOUND'
        );
      end if;
      raise;
  end;

  begin
    v_code := private.normalize_family_code(p_code);
  exception
    when sqlstate 'P0001' then
      perform private.record_invalid_family_code_attempt(v_account_id);
      return pg_catalog.jsonb_build_object(
        'errorCode',
        'FAMILY_NOT_FOUND'
      );
  end;

  select code.*
  into v_family_code
  from public.family_join_codes as code
  where code.code_hash = extensions.digest(v_code, 'sha256')
  for share;

  if not found then
    perform private.record_invalid_family_code_attempt(v_account_id);
    return pg_catalog.jsonb_build_object(
      'errorCode',
      'FAMILY_NOT_FOUND'
    );
  end if;
  perform private.clear_invalid_family_code_attempts(v_account_id);

  select family.name
  into v_family_name
  from public.cloud_families as family
  where family.id = v_family_code.family_id;

  if v_family_name is null then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;

  select pg_catalog.coalesce(
    pg_catalog.jsonb_agg(
      private.family_member_json(membership)
      order by membership.joined_at, membership.member_id
    ),
    '[]'::pg_catalog.jsonb
  )
  into v_members
  from public.family_memberships as membership
  where membership.family_id = v_family_code.family_id
    and membership.state = 'active';

  return pg_catalog.jsonb_build_object(
    'familyId', v_family_code.family_id::pg_catalog.text,
    'familyName', v_family_name,
    'codeVersion', v_family_code.code_version,
    'members', v_members
  );
end;
$function$;

create or replace function public.create_family_join_request(
  p_family_id pg_catalog.uuid,
  p_code pg_catalog.text,
  p_member_id pg_catalog.uuid,
  p_display_name pg_catalog.text,
  p_demographic_role pg_catalog.text,
  p_color_token pg_catalog.text,
  p_avatar_json pg_catalog.jsonb,
  p_joining_public_key pg_catalog.text
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_code pg_catalog.text;
  v_family_code public.family_join_codes%rowtype;
  v_existing public.family_join_requests%rowtype;
  v_request public.family_join_requests%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  perform private.expire_family_join_requests();

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.create_family_join_request.v1:'::pg_catalog.text
        || v_account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  begin
    perform private.check_family_code_account_limit(v_account_id);
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'FAMILY_NOT_FOUND' then
        return pg_catalog.jsonb_build_object(
          'errorCode',
          'FAMILY_NOT_FOUND'
        );
      end if;
      raise;
  end;

  begin
    v_code := private.normalize_family_code(p_code);
  exception
    when sqlstate 'P0001' then
      perform private.record_invalid_family_code_attempt(v_account_id);
      return pg_catalog.jsonb_build_object(
        'errorCode',
        'FAMILY_NOT_FOUND'
      );
  end;

  select code.*
  into v_family_code
  from public.family_join_codes as code
  where code.family_id = p_family_id
    and code.code_hash = extensions.digest(v_code, 'sha256')
  for share;

  if not found then
    perform private.record_invalid_family_code_attempt(v_account_id);
    return pg_catalog.jsonb_build_object(
      'errorCode',
      'FAMILY_NOT_FOUND'
    );
  end if;
  perform private.clear_invalid_family_code_attempts(v_account_id);

  if exists (
    select 1
    from public.family_memberships as membership
    where membership.account_id = v_account_id
      and membership.state = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'ALREADY_MEMBER';
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
    or not private.is_canonical_base64url(p_joining_public_key, 32)
  then
    raise exception using errcode = 'P0001', message = 'INVALID_JOIN_KEY';
  end if;

  select request.*
  into v_existing
  from public.family_join_requests as request
  where request.requester_account_id = v_account_id
    and request.state in ('pending', 'approved')
  for update;

  if found then
    if v_existing.family_id is distinct from p_family_id
      or v_existing.member_id is distinct from p_member_id
      or v_existing.display_name is distinct from p_display_name
      or v_existing.demographic_role is distinct from
        p_demographic_role::public.family_demographic_role
      or v_existing.color_token is distinct from p_color_token
      or v_existing.avatar_json is distinct from p_avatar_json
      or v_existing.joining_public_key is distinct from p_joining_public_key
      or v_existing.code_version is distinct from v_family_code.code_version
    then
      raise exception using errcode = 'P0001', message = 'REQUEST_ALREADY_PENDING';
    end if;
    return private.own_family_join_request_json(v_existing);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.family_join_request_family_quota.v1:'::pg_catalog.text
        || p_family_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  if (
    select pg_catalog.count(*)
    from public.family_join_requests as request
    where request.family_id = p_family_id
      and request.state = 'pending'
  ) >= 100 then
    raise exception using errcode = 'P0001', message = 'RATE_LIMITED';
  end if;

  if (
    select pg_catalog.count(*)
    from public.family_join_requests as request
    where request.requester_account_id = v_account_id
      and request.created_at >= pg_catalog.clock_timestamp() - interval '1 hour'
  ) >= 10 then
    raise exception using errcode = 'P0001', message = 'RATE_LIMITED';
  end if;

  v_now := pg_catalog.clock_timestamp();
  begin
    insert into public.family_join_requests (
      family_id,
      requester_account_id,
      member_id,
      display_name,
      demographic_role,
      color_token,
      avatar_json,
      joining_public_key,
      code_version,
      created_at,
      expires_at,
      updated_at
    ) values (
      p_family_id,
      v_account_id,
      p_member_id,
      p_display_name,
      p_demographic_role::public.family_demographic_role,
      p_color_token,
      p_avatar_json,
      p_joining_public_key,
      v_family_code.code_version,
      v_now,
      v_now + interval '7 days',
      v_now
    )
    returning * into v_request;
  exception
    when unique_violation then
      select request.*
      into v_existing
      from public.family_join_requests as request
      where request.requester_account_id = v_account_id
        and request.state in ('pending', 'approved')
      for update;
      if found
        and v_existing.family_id is not distinct from p_family_id
        and v_existing.member_id is not distinct from p_member_id
        and v_existing.display_name is not distinct from p_display_name
        and v_existing.demographic_role is not distinct from
          p_demographic_role::public.family_demographic_role
        and v_existing.color_token is not distinct from p_color_token
        and v_existing.avatar_json is not distinct from p_avatar_json
        and v_existing.joining_public_key is not distinct from p_joining_public_key
        and v_existing.code_version is not distinct from v_family_code.code_version
      then
        return private.own_family_join_request_json(v_existing);
      end if;
      raise exception using errcode = 'P0001', message = 'REQUEST_ALREADY_PENDING';
  end;

  return private.own_family_join_request_json(v_request);
end;
$function$;

create or replace function public.list_pending_family_join_requests(
  p_family_id pg_catalog.uuid
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_requests pg_catalog.jsonb;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  perform private.expire_family_join_requests();

  if p_family_id is null
    or not private.is_active_family_member(p_family_id)
  then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  select pg_catalog.coalesce(
    pg_catalog.jsonb_agg(
      private.pending_family_join_request_json(request)
      order by request.created_at, request.id
    ),
    '[]'::pg_catalog.jsonb
  )
  into v_requests
  from public.family_join_requests as request
  where request.family_id = p_family_id
    and request.state = 'pending';

  return v_requests;
end;
$function$;

create or replace function public.get_own_family_join_request()
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_request public.family_join_requests%rowtype;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  perform private.expire_family_join_requests();

  select request.*
  into v_request
  from public.family_join_requests as request
  where request.requester_account_id = v_account_id
  order by
    (request.state in ('pending', 'approved')) desc,
    request.created_at desc,
    request.id desc
  limit 1;

  if not found then
    return null;
  end if;
  return private.own_family_join_request_json(v_request);
end;
$function$;

create or replace function public.approve_family_join_request(
  p_request_id pg_catalog.uuid,
  p_approval_envelope pg_catalog.jsonb
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_request public.family_join_requests%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  if p_request_id is null then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;
  perform private.expire_family_join_requests();

  select request.*
  into v_request
  from public.family_join_requests as request
  where request.id = p_request_id
  for update;

  if not found
    or not private.is_active_family_member(v_request.family_id)
  then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  if v_request.state <> 'pending' then
    return private.family_join_request_decision_json(v_request);
  end if;

  v_now := pg_catalog.clock_timestamp();
  if v_request.expires_at <= v_now then
    update public.family_join_requests
    set
      state = 'expired',
      resolved_at = v_now,
      updated_at = v_now
    where id = v_request.id
      and state = 'pending'
    returning * into v_request;
    return private.family_join_request_decision_json(v_request);
  end if;

  if p_approval_envelope is null
    or pg_catalog.jsonb_typeof(p_approval_envelope) <> 'object'
    or (
      select pg_catalog.count(*)
      from pg_catalog.jsonb_object_keys(p_approval_envelope)
    ) <> 9
    or exists (
      select 1
      from pg_catalog.jsonb_object_keys(p_approval_envelope) as envelope_key(key)
      where envelope_key.key not in (
        'version', 'requestId', 'familyId', 'requesterAccountId',
        'codeVersion', 'ephemeralPublicKey', 'nonce', 'ciphertext', 'mac'
      )
    )
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'version') <> 'number'
    or p_approval_envelope ->> 'version' <> '1'
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'requestId') <> 'string'
    or p_approval_envelope ->> 'requestId' <> v_request.id::pg_catalog.text
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'familyId') <> 'string'
    or p_approval_envelope ->> 'familyId' <> v_request.family_id::pg_catalog.text
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'requesterAccountId') <> 'string'
    or p_approval_envelope ->> 'requesterAccountId'
      <> v_request.requester_account_id::pg_catalog.text
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'codeVersion') <> 'number'
    or p_approval_envelope ->> 'codeVersion'
      <> v_request.code_version::pg_catalog.text
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'ephemeralPublicKey')
      <> 'string'
    or not private.is_canonical_base64url(
      p_approval_envelope ->> 'ephemeralPublicKey',
      32
    )
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'nonce') <> 'string'
    or not private.is_canonical_base64url(
      p_approval_envelope ->> 'nonce',
      12
    )
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'ciphertext') <> 'string'
    or not private.is_canonical_base64url(
      p_approval_envelope ->> 'ciphertext',
      32
    )
    or pg_catalog.jsonb_typeof(p_approval_envelope -> 'mac') <> 'string'
    or not private.is_canonical_base64url(
      p_approval_envelope ->> 'mac',
      16
    )
  then
    raise exception using errcode = 'P0001', message = 'ENVELOPE_REJECTED';
  end if;

  v_now := pg_catalog.clock_timestamp();
  update public.family_join_requests
  set
    state = 'approved',
    decision_account_id = v_account_id,
    approval_envelope_version = 1,
    approval_ephemeral_public_key = p_approval_envelope ->> 'ephemeralPublicKey',
    approval_nonce = p_approval_envelope ->> 'nonce',
    approval_ciphertext = p_approval_envelope ->> 'ciphertext',
    approval_mac = p_approval_envelope ->> 'mac',
    resolved_at = v_now,
    updated_at = v_now
  where id = v_request.id
  returning * into v_request;

  return private.family_join_request_decision_json(v_request);
end;
$function$;

create or replace function public.decline_family_join_request(
  p_request_id pg_catalog.uuid
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_request public.family_join_requests%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  if p_request_id is null then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;
  perform private.expire_family_join_requests();

  select request.*
  into v_request
  from public.family_join_requests as request
  where request.id = p_request_id
  for update;

  if not found
    or not private.is_active_family_member(v_request.family_id)
  then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  if v_request.state <> 'pending' then
    return private.family_join_request_decision_json(v_request);
  end if;

  v_now := pg_catalog.clock_timestamp();
  if v_request.expires_at <= v_now then
    update public.family_join_requests
    set
      state = 'expired',
      resolved_at = v_now,
      updated_at = v_now
    where id = v_request.id
      and state = 'pending'
    returning * into v_request;
    return private.family_join_request_decision_json(v_request);
  end if;

  update public.family_join_requests
  set
    state = 'declined',
    decision_account_id = v_account_id,
    resolved_at = v_now,
    updated_at = v_now
  where id = v_request.id
  returning * into v_request;

  return private.family_join_request_decision_json(v_request);
end;
$function$;

create or replace function public.cancel_family_join_request(
  p_request_id pg_catalog.uuid
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_request public.family_join_requests%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  perform private.expire_family_join_requests();

  select request.*
  into v_request
  from public.family_join_requests as request
  where request.id = p_request_id
    and request.requester_account_id = v_account_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  if v_request.state <> 'pending' then
    return private.family_join_request_decision_json(v_request);
  end if;

  v_now := pg_catalog.clock_timestamp();
  if v_request.expires_at <= v_now then
    update public.family_join_requests
    set
      state = 'expired',
      resolved_at = v_now,
      updated_at = v_now
    where id = v_request.id
      and state = 'pending'
    returning * into v_request;
    return private.family_join_request_decision_json(v_request);
  end if;

  update public.family_join_requests
  set
    state = 'cancelled',
    cancel_reason = 'requester',
    resolved_at = v_now,
    updated_at = v_now
  where id = v_request.id
  returning * into v_request;

  return private.family_join_request_decision_json(v_request);
end;
$function$;

create or replace function public.complete_family_join_request(
  p_request_id pg_catalog.uuid
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_request public.family_join_requests%rowtype;
  v_membership public.family_memberships%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  perform private.expire_family_join_requests();

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.family_membership_install.v1:'::pg_catalog.text
        || v_account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  select request.*
  into v_request
  from public.family_join_requests as request
  where request.id = p_request_id
    and request.requester_account_id = v_account_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  if v_request.state = 'installed' then
    return private.family_join_request_decision_json(v_request);
  end if;
  if v_request.state = 'pending' then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  elsif v_request.state = 'declined' then
    raise exception using errcode = 'P0001', message = 'REQUEST_DECLINED';
  elsif v_request.state = 'expired' then
    raise exception using errcode = 'P0001', message = 'REQUEST_EXPIRED';
  elsif v_request.state = 'cancelled'
    and v_request.cancel_reason = 'code_regenerated'
  then
    raise exception using errcode = 'P0001', message = 'INVITATION_CHANGED';
  elsif v_request.state = 'cancelled' then
    raise exception using errcode = 'P0001', message = 'REQUEST_CANCELLED';
  elsif v_request.state <> 'approved' then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  select membership.*
  into v_membership
  from public.family_memberships as membership
  where membership.account_id = v_account_id
  for update;

  if found then
    raise exception using errcode = 'P0001', message = 'ALREADY_MEMBER';
  end if;

  v_now := pg_catalog.clock_timestamp();
  insert into public.profiles (
    account_id, display_name, created_at, updated_at
  ) values (
    v_account_id, v_request.display_name, v_now, v_now
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
    ) values (
      v_request.family_id,
      v_account_id,
      v_request.member_id,
      v_request.display_name,
      v_request.demographic_role,
      v_request.color_token,
      v_request.avatar_json,
      'member',
      'active',
      v_now,
      v_now,
      v_now
    );
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'ALREADY_MEMBER';
  end;

  update public.family_join_requests
  set
    state = 'installed',
    updated_at = v_now
  where id = v_request.id
  returning * into v_request;

  return private.family_join_request_decision_json(v_request);
end;
$function$;

create or replace function public.regenerate_family_join_code(
  p_family_id pg_catalog.uuid,
  p_expected_version pg_catalog.integer,
  p_code pg_catalog.text,
  p_code_envelope pg_catalog.jsonb
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_code pg_catalog.text;
  v_existing public.family_join_codes%rowtype;
  v_now pg_catalog.timestamptz;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  perform private.expire_family_join_requests();
  if p_family_id is null
    or not exists (
      select 1
      from public.cloud_families as family
      join public.family_memberships as membership
        on membership.family_id = family.id
       and membership.account_id = v_account_id
       and membership.membership_role = 'owner'
       and membership.state = 'active'
      where family.id = p_family_id
        and family.owner_account_id = v_account_id
    )
  then
    raise exception using errcode = 'P0001', message = 'NOT_CREATOR';
  end if;

  v_code := private.normalize_family_code(p_code);

  select code.*
  into v_existing
  from public.family_join_codes as code
  where code.family_id = p_family_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;
  if p_expected_version is null
    or p_expected_version <> v_existing.code_version
  then
    raise exception using errcode = 'P0001', message = 'CODE_VERSION_CHANGED';
  end if;
  if extensions.digest(v_code, 'sha256') = v_existing.code_hash then
    raise exception using errcode = 'P0001', message = 'CODE_COLLISION';
  end if;
  if not private.is_valid_family_code_envelope(
    p_code_envelope,
    p_family_id,
    v_existing.code_version + 1
  ) then
    raise exception using errcode = 'P0001', message = 'ENVELOPE_REJECTED';
  end if;

  v_now := pg_catalog.clock_timestamp();
  begin
    update public.family_join_codes
    set
      code_version = v_existing.code_version + 1,
      code_hash = extensions.digest(v_code, 'sha256'),
      envelope_version = (p_code_envelope ->> 'codecVersion')::pg_catalog.integer,
      nonce = p_code_envelope ->> 'nonce',
      ciphertext = p_code_envelope ->> 'ciphertext',
      mac = p_code_envelope ->> 'mac',
      updated_at = v_now
    where family_id = p_family_id;
  exception
    when unique_violation then
      raise exception using errcode = 'P0001', message = 'CODE_COLLISION';
  end;

  update public.family_join_requests
  set
    state = 'cancelled',
    cancel_reason = 'code_regenerated',
    resolved_at = v_now,
    updated_at = v_now
  where family_id = p_family_id
    and state = 'pending'
    and code_version = v_existing.code_version;

  select code.*
  into v_existing
  from public.family_join_codes as code
  where code.family_id = p_family_id;
  return private.family_join_code_json(v_existing);
end;
$function$;

revoke execute on function public.bootstrap_owner_family_with_code(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.jsonb,
  pg_catalog.text,
  pg_catalog.jsonb
) from public, anon, authenticated;
grant execute on function public.bootstrap_owner_family_with_code(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.jsonb,
  pg_catalog.text,
  pg_catalog.jsonb
) to authenticated;

revoke execute on function public.get_family_join_code(pg_catalog.uuid)
  from public, anon, authenticated;
grant execute on function public.get_family_join_code(pg_catalog.uuid)
  to authenticated;

revoke execute on function public.preview_family_by_code(pg_catalog.text)
  from public, anon, authenticated;
grant execute on function public.preview_family_by_code(pg_catalog.text)
  to authenticated;

revoke execute on function public.create_family_join_request(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.jsonb,
  pg_catalog.text
) from public, anon, authenticated;
grant execute on function public.create_family_join_request(
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.jsonb,
  pg_catalog.text
) to authenticated;

revoke execute on function public.list_pending_family_join_requests(
  pg_catalog.uuid
) from public, anon, authenticated;
grant execute on function public.list_pending_family_join_requests(
  pg_catalog.uuid
) to authenticated;

revoke execute on function public.get_own_family_join_request()
  from public, anon, authenticated;
grant execute on function public.get_own_family_join_request()
  to authenticated;

revoke execute on function public.approve_family_join_request(
  pg_catalog.uuid,
  pg_catalog.jsonb
) from public, anon, authenticated;
grant execute on function public.approve_family_join_request(
  pg_catalog.uuid,
  pg_catalog.jsonb
) to authenticated;

revoke execute on function public.decline_family_join_request(pg_catalog.uuid)
  from public, anon, authenticated;
grant execute on function public.decline_family_join_request(pg_catalog.uuid)
  to authenticated;

revoke execute on function public.cancel_family_join_request(pg_catalog.uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_family_join_request(pg_catalog.uuid)
  to authenticated;

revoke execute on function public.complete_family_join_request(pg_catalog.uuid)
  from public, anon, authenticated;
grant execute on function public.complete_family_join_request(pg_catalog.uuid)
  to authenticated;

revoke execute on function public.regenerate_family_join_code(
  pg_catalog.uuid,
  pg_catalog.integer,
  pg_catalog.text,
  pg_catalog.jsonb
) from public, anon, authenticated;
grant execute on function public.regenerate_family_join_code(
  pg_catalog.uuid,
  pg_catalog.integer,
  pg_catalog.text,
  pg_catalog.jsonb
) to authenticated;
