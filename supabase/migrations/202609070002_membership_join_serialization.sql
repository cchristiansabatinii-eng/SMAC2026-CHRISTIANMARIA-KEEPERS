-- Serialize every membership-producing path with family-code requests.
-- This closes the compatibility race between legacy invitation claims and the
-- permanent-code two-phase installer without exposing any new client RPC.

do $migration_guard$
begin
  if exists (
    select 1
    from public.family_join_requests as request
    join public.family_memberships as membership
      on membership.account_id = request.requester_account_id
    where request.state in ('pending', 'approved')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'EXISTING_MEMBERSHIP_JOIN_CONFLICT';
  end if;
end
$migration_guard$;

create or replace function private.guard_family_join_request_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.family_membership_account.v1:'::pg_catalog.text
        || new.requester_account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  if exists (
    select 1
    from public.family_memberships as membership
    where membership.account_id = new.requester_account_id
  ) then
    raise exception using errcode = 'P0001', message = 'ALREADY_MEMBER';
  end if;

  return new;
end
$function$;

revoke execute on function private.guard_family_join_request_membership()
from public, anon, authenticated;

drop trigger if exists guard_family_join_request_membership
on public.family_join_requests;

create trigger guard_family_join_request_membership
before insert on public.family_join_requests
for each row execute function private.guard_family_join_request_membership();

create or replace function private.guard_family_membership_join_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.family_membership_account.v1:'::pg_catalog.text
        || new.account_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  if exists (
    select 1
    from public.family_join_requests as request
    where request.requester_account_id = new.account_id
      and request.state in ('pending', 'approved')
      and not (
        request.state = 'approved'
        and new.state = 'active'
        and new.membership_role = 'member'
        and request.family_id = new.family_id
        and request.member_id = new.member_id
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'JOIN_REQUEST_IN_PROGRESS';
  end if;

  return new;
end
$function$;

revoke execute on function private.guard_family_membership_join_request()
from public, anon, authenticated;

drop trigger if exists guard_family_membership_join_request
on public.family_memberships;

create trigger guard_family_membership_join_request
before insert on public.family_memberships
for each row execute function private.guard_family_membership_join_request();

