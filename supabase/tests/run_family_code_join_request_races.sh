#!/usr/bin/env bash
set -euo pipefail

command -v psql >/dev/null || { echo 'psql is required' >&2; exit 1; }

db_url="${DB_URL:-}"
if [[ -z "$db_url" ]]; then
  db_url="$(supabase status -o env | sed -n 's/^DB_URL="\([^"]*\)"$/\1/p')"
fi
[[ -n "$db_url" ]] || { echo 'Supabase DB_URL was not available' >&2; exit 1; }

race_tmp="$(mktemp -d)"
case "$race_tmp" in /tmp/*) ;; *) echo "unsafe temp path: $race_tmp" >&2; exit 1 ;; esac
psql_base=(psql "$db_url" -X -v ON_ERROR_STOP=1 -Atq)
pid_a=''
pid_b=''
barrier_pid=''

clean_database() {
  local cleanup_status=0
  "${psql_base[@]}" <<'SQL' || cleanup_status=$?
delete from public.family_join_requests
where id in (
  'c0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000002',
  'c0000000-0000-4000-8000-000000000004',
  'c0000000-0000-4000-8000-000000000005',
  'c0000000-0000-4000-8000-000000000006'
)
or requester_account_id in (
  'b0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000004',
  'b0000000-0000-4000-8000-000000000005'
);
delete from public.family_memberships
where family_id in (
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002'
)
or account_id in (
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000004',
  'b0000000-0000-4000-8000-000000000005'
);
delete from public.family_join_codes
where family_id in (
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002'
);
delete from public.cloud_families
where id in (
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002'
);
delete from public.profiles
where account_id in (
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000004',
  'b0000000-0000-4000-8000-000000000005'
);
delete from private.family_code_account_limits
where account_id in (
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000004',
  'b0000000-0000-4000-8000-000000000005'
);
delete from auth.users
where id in (
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000003',
  'b0000000-0000-4000-8000-000000000004',
  'b0000000-0000-4000-8000-000000000005'
);
SQL
  "${psql_base[@]}" -c "
    create unique index if not exists family_join_requests_account_unresolved_idx
      on public.family_join_requests(requester_account_id)
      where state in ('pending', 'approved')
  " || cleanup_status=$?
  return "$cleanup_status"
}

cleanup() {
  local original_status="$?" cleanup_status=0 pid
  trap - EXIT INT TERM
  set +e
  for pid in "$pid_a" "$pid_b" "$barrier_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; fi
  done
  for pid in "$pid_a" "$pid_b" "$barrier_pid"; do
    if [[ -n "$pid" ]]; then wait "$pid" 2>/dev/null; fi
  done
  clean_database || cleanup_status=$?
  rm -rf -- "$race_tmp"
  if [[ "$original_status" == 0 && "$cleanup_status" != 0 ]]; then
    original_status="$cleanup_status"
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { echo "race harness: $*" >&2; exit 1; }
assert_sql() {
  local expected="$1" query="$2" actual
  actual="$("${psql_base[@]}" -c "$query")"
  [[ "$actual" == "$expected" ]] || fail "expected [$expected], got [$actual] for: $query"
}
last_json() { grep -E '^\{' "$1" | tail -n 1 || true; }

start_barrier() {
  local key="$1" line
  coproc RACE_LOCK { PGAPPNAME="keepers-race-barrier-$key" "${psql_base[@]}"; }
  barrier_pid="$RACE_LOCK_PID"
  barrier_read="${RACE_LOCK[0]}"
  barrier_write="${RACE_LOCK[1]}"
  printf 'select pg_advisory_lock(%s);\n\\echo READY\n' "$key" >&"$barrier_write"
  while IFS= read -r line <&"$barrier_read"; do
    [[ "$line" == 'READY' ]] && return
  done
  fail "barrier $key did not become ready"
}

wait_for_workers() {
  local app_a="$1" app_b="$2" count
  for _ in {1..100}; do
    count="$("${psql_base[@]}" -c "
      select count(*)
      from pg_catalog.pg_stat_activity
      where application_name in ('$app_a', '$app_b')
        and wait_event_type = 'Lock'
        and wait_event = 'advisory'
    ")"
    [[ "$count" == '2' ]] && return
    sleep 0.1
  done
  fail "workers $app_a and $app_b did not reach the advisory barrier"
}

release_barrier() {
  local key="$1"
  printf 'select pg_advisory_unlock(%s);\n\\q\n' "$key" >&"$barrier_write"
  wait "$barrier_pid"
  barrier_pid=''
  unset RACE_LOCK RACE_LOCK_PID || true
}

run_race() {
  local key="$1" tag="$2" sql_a="$3" sql_b="$4"
  start_barrier "$key"
  PGAPPNAME="keepers-race-$tag-a" "${psql_base[@]}" -v barrier="$key" -f "$sql_a" \
    >"$race_tmp/$tag-a.out" 2>"$race_tmp/$tag-a.err" &
  pid_a=$!
  PGAPPNAME="keepers-race-$tag-b" "${psql_base[@]}" -v barrier="$key" -f "$sql_b" \
    >"$race_tmp/$tag-b.out" 2>"$race_tmp/$tag-b.err" &
  pid_b=$!
  wait_for_workers "keepers-race-$tag-a" "keepers-race-$tag-b"
  release_barrier "$key"
  set +e
  wait "$pid_a"; status_a=$?
  wait "$pid_b"; status_b=$?
  set -e
  pid_a=''
  pid_b=''
}

clean_database

"${psql_base[@]}" <<'SQL'
insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000', id, 'authenticated',
  'authenticated', email, '', clock_timestamp(),
  '{"provider":"email","providers":["email"]}', '{}',
  clock_timestamp(), clock_timestamp()
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'race-owner-a@example.com'),
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'race-member-a@example.com'),
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'race-owner-b@example.com'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'race-approve@example.com'),
  ('b0000000-0000-4000-8000-000000000002'::uuid, 'race-decision@example.com'),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 'race-regenerate@example.com'),
  ('b0000000-0000-4000-8000-000000000004'::uuid, 'race-expiry@example.com'),
  ('b0000000-0000-4000-8000-000000000005'::uuid, 'race-two-families@example.com')
) fixture(id, email);

insert into public.profiles(account_id, display_name) values
  ('a0000000-0000-4000-8000-000000000001', 'Race owner A'),
  ('a0000000-0000-4000-8000-000000000002', 'Race member A'),
  ('a0000000-0000-4000-8000-000000000003', 'Race owner B');
insert into public.cloud_families(id, name, owner_account_id) values
  ('a1000000-0000-4000-8000-000000000001', 'Race family A', 'a0000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002', 'Race family B', 'a0000000-0000-4000-8000-000000000003');
insert into public.family_memberships(
  family_id, account_id, member_id, display_name, demographic_role,
  color_token, avatar_json, membership_role, state
) values
  ('a1000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'Race owner A', 'adult', 'ochre', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"roa","selections":{},"colors":{}}', 'owner', 'active'),
  ('a1000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000002', 'Race member A', 'adult', 'plum', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"rma","selections":{},"colors":{}}', 'member', 'active'),
  ('a1000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-000000000003', 'Race owner B', 'adult', 'sage', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"rob","selections":{},"colors":{}}', 'owner', 'active');
insert into public.family_join_codes(
  family_id, code_version, code_hash, envelope_version, nonce,
  ciphertext, mac, creator_account_id
) values
  ('a1000000-0000-4000-8000-000000000001', 1, extensions.digest('ABCD2345', 'sha256'), 1, 'AAECAwQFBgcICQoL', 'AAECAwQFBgc', 'AAECAwQFBgcICQoLDA0ODw', 'a0000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002', 1, extensions.digest('BCDE3456', 'sha256'), 1, 'AQIDBAUGBwgJCgsM', 'AQIDBAUGBwg', 'AQIDBAUGBwgJCgsMDQ4PEA', 'a0000000-0000-4000-8000-000000000003');

insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, created_at, expires_at, updated_at
) values
  ('c0000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Approve race', 'adult', 'blue', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r1","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 1, statement_timestamp(), statement_timestamp() + interval '7 days', statement_timestamp()),
  ('c0000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'Decision race', 'adult', 'rose', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r2","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 1, statement_timestamp(), statement_timestamp() + interval '7 days', statement_timestamp()),
  ('c0000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000004', 'Expiry race', 'adult', 'gold', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r4","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 1, statement_timestamp(), statement_timestamp() + interval '7 days', statement_timestamp());
SQL

cat >"$race_tmp/approve-a.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000001';
select public.approve_family_join_request('c0000000-0000-4000-8000-000000000001', '{"version":1,"requestId":"c0000000-0000-4000-8000-000000000001","familyId":"a1000000-0000-4000-8000-000000000001","requesterAccountId":"b0000000-0000-4000-8000-000000000001","codeVersion":1,"ephemeralPublicKey":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","nonce":"AAECAwQFBgcICQoL","ciphertext":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","mac":"AAECAwQFBgcICQoLDA0ODw"}');
commit;
SQL
cat >"$race_tmp/approve-b.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000002';
select public.approve_family_join_request('c0000000-0000-4000-8000-000000000001', '{"version":1,"requestId":"c0000000-0000-4000-8000-000000000001","familyId":"a1000000-0000-4000-8000-000000000001","requesterAccountId":"b0000000-0000-4000-8000-000000000001","codeVersion":1,"ephemeralPublicKey":"AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA","nonce":"AQIDBAUGBwgJCgsM","ciphertext":"AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA","mac":"AQIDBAUGBwgJCgsMDQ4PEA"}');
commit;
SQL
run_race 51001 approve "$race_tmp/approve-a.sql" "$race_tmp/approve-b.sql"
[[ "$status_a" == 0 && "$status_b" == 0 ]] || fail 'approve/approve worker failed'
[[ "$(last_json "$race_tmp/approve-a.out")" == "$(last_json "$race_tmp/approve-b.out")" ]] || fail 'approve/approve did not return one authoritative decision'
assert_sql 'approved|1|1' "select state || '|' || (decision_account_id is not null)::int || '|' || (approval_ciphertext is not null)::int from public.family_join_requests where id = 'c0000000-0000-4000-8000-000000000001'"

cat >"$race_tmp/decision-a.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000001';
select public.approve_family_join_request('c0000000-0000-4000-8000-000000000002', '{"version":1,"requestId":"c0000000-0000-4000-8000-000000000002","familyId":"a1000000-0000-4000-8000-000000000001","requesterAccountId":"b0000000-0000-4000-8000-000000000002","codeVersion":1,"ephemeralPublicKey":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","nonce":"AAECAwQFBgcICQoL","ciphertext":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","mac":"AAECAwQFBgcICQoLDA0ODw"}'); commit;
SQL
cat >"$race_tmp/decision-b.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000002';
select public.decline_family_join_request('c0000000-0000-4000-8000-000000000002'); commit;
SQL
run_race 51002 decision "$race_tmp/decision-a.sql" "$race_tmp/decision-b.sql"
[[ "$status_a" == 0 && "$status_b" == 0 ]] || fail 'approve/decline worker failed'
[[ "$(last_json "$race_tmp/decision-a.out")" == "$(last_json "$race_tmp/decision-b.out")" ]] || fail 'approve/decline did not return one authoritative decision'
assert_sql '1' "select (state in ('approved','declined') and decision_account_id is not null)::int from public.family_join_requests where id = 'c0000000-0000-4000-8000-000000000002'"

cat >"$race_tmp/regenerate-a.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000001';
select public.regenerate_family_join_code('a1000000-0000-4000-8000-000000000001', 1, 'CDEF4567', '{"codecVersion":1,"familyId":"a1000000-0000-4000-8000-000000000001","codeVersion":2,"nonce":"AgMEBQYHCAkKCwwN","ciphertext":"AgMEBQYHCAk","mac":"AgMEBQYHCAkKCwwNDg8QEQ"}'); commit;
SQL
cat >"$race_tmp/regenerate-b.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'b0000000-0000-4000-8000-000000000003';
select public.create_family_join_request('a1000000-0000-4000-8000-000000000001', 'ABCD2345', 'd0000000-0000-4000-8000-000000000003', 'Regenerate race', 'adult', 'mint', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r3","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'); commit;
SQL
run_race 51003 regenerate "$race_tmp/regenerate-a.sql" "$race_tmp/regenerate-b.sql"
[[ "$status_a" == 0 && "$status_b" == 0 ]] || fail 'regenerate/request worker failed'
assert_sql '2|0|1' "select c.code_version || '|' || count(r.id) filter (where r.state = 'pending') || '|' || (count(r.id) <= 1)::int from public.family_join_codes c left join public.family_join_requests r on r.requester_account_id = 'b0000000-0000-4000-8000-000000000003' where c.family_id = 'a1000000-0000-4000-8000-000000000001' group by c.code_version"
assert_sql '1' "select coalesce(bool_and(state = 'cancelled' and cancel_reason = 'code_regenerated'), true)::int from public.family_join_requests where requester_account_id = 'b0000000-0000-4000-8000-000000000003'"

"${psql_base[@]}" <<'SQL'
delete from public.family_join_requests
where id = 'c0000000-0000-4000-8000-000000000004';
insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name,
  demographic_role, color_token, avatar_json, joining_public_key,
  code_version, created_at, expires_at, updated_at
) values (
  'c0000000-0000-4000-8000-000000000004',
  'a1000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000004',
  'd0000000-0000-4000-8000-000000000004',
  'Expiry race', 'adult', 'gold',
  '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r4","selections":{},"colors":{}}',
  'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  2, statement_timestamp(), statement_timestamp() + interval '7 days',
  statement_timestamp()
);
SQL

cat >"$race_tmp/expiry-a.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'a0000000-0000-4000-8000-000000000001';
select public.approve_family_join_request('c0000000-0000-4000-8000-000000000004', '{"version":1,"requestId":"c0000000-0000-4000-8000-000000000004","familyId":"a1000000-0000-4000-8000-000000000001","requesterAccountId":"b0000000-0000-4000-8000-000000000004","codeVersion":2,"ephemeralPublicKey":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","nonce":"AAECAwQFBgcICQoL","ciphertext":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","mac":"AAECAwQFBgcICQoLDA0ODw"}');
set local "request.jwt.claim.sub" = 'b0000000-0000-4000-8000-000000000004';
select public.complete_family_join_request('c0000000-0000-4000-8000-000000000004'); commit;
SQL
cat >"$race_tmp/expiry-b.sql" <<'SQL'
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier);
with boundary as (select clock_timestamp() - interval '7 days' created)
update public.family_join_requests r set created_at = boundary.created, expires_at = boundary.created + interval '7 days', updated_at = clock_timestamp() from boundary where id = 'c0000000-0000-4000-8000-000000000004';
select private.expire_family_join_requests(); commit;
SQL
run_race 51004 expiry "$race_tmp/expiry-a.sql" "$race_tmp/expiry-b.sql"
[[ "$status_b" == 0 ]] || fail 'expiry worker failed'
if [[ "$status_a" != 0 ]] && ! grep -q 'REQUEST_EXPIRED' "$race_tmp/expiry-a.err"; then fail 'completion failed for an unexpected reason'; fi
assert_sql '1' "select ((state = 'installed' and (select count(*) = 1 from public.family_memberships where account_id = 'b0000000-0000-4000-8000-000000000004')) or (state = 'expired' and (select count(*) = 0 from public.family_memberships where account_id = 'b0000000-0000-4000-8000-000000000004')))::int from public.family_join_requests where id = 'c0000000-0000-4000-8000-000000000004'"

"${psql_base[@]}" <<'SQL'
drop index public.family_join_requests_account_unresolved_idx;
insert into public.family_join_requests(
  id, family_id, requester_account_id, member_id, display_name, demographic_role,
  color_token, avatar_json, joining_public_key, code_version, state,
  decision_account_id, approval_envelope_version, approval_ephemeral_public_key,
  approval_nonce, approval_ciphertext, approval_mac, created_at, expires_at,
  resolved_at, updated_at
) values
  ('c0000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000005', 'Two families', 'adult', 'blue', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r5a","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 2, 'approved', 'a0000000-0000-4000-8000-000000000001', 1, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 'AAECAwQFBgcICQoL', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 'AAECAwQFBgcICQoLDA0ODw', statement_timestamp(), statement_timestamp() + interval '7 days', statement_timestamp(), statement_timestamp()),
  ('c0000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000006', 'Two families', 'adult', 'blue', '{"schemaVersion":2,"styleId":"humation-1","styleRevision":1,"seed":"r5b","selections":{},"colors":{}}', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 1, 'approved', 'a0000000-0000-4000-8000-000000000003', 1, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 'AAECAwQFBgcICQoL', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8', 'AAECAwQFBgcICQoLDA0ODw', statement_timestamp(), statement_timestamp() + interval '7 days', statement_timestamp(), statement_timestamp());
SQL
for side in a b; do
  request_id='c0000000-0000-4000-8000-000000000005'
  [[ "$side" == b ]] && request_id='c0000000-0000-4000-8000-000000000006'
  cat >"$race_tmp/two-$side.sql" <<SQL
begin; set local lock_timeout = '15s'; set local statement_timeout = '30s';
select pg_advisory_xact_lock(:barrier); set local role authenticated;
set local "request.jwt.claim.sub" = 'b0000000-0000-4000-8000-000000000005';
select public.complete_family_join_request('$request_id'); commit;
SQL
done
run_race 51005 two "$race_tmp/two-a.sql" "$race_tmp/two-b.sql"
if [[ "$status_a" == 0 && "$status_b" == 0 ]] || [[ "$status_a" != 0 && "$status_b" != 0 ]]; then fail 'exactly one two-family completion must succeed'; fi
grep -q 'ALREADY_MEMBER' "$race_tmp/two-a.err" "$race_tmp/two-b.err" || fail 'losing two-family completion was not typed ALREADY_MEMBER'
assert_sql '1|1|1' "select (select count(*) from public.family_memberships where account_id = 'b0000000-0000-4000-8000-000000000005') || '|' || (select count(*) from public.family_join_requests where requester_account_id = 'b0000000-0000-4000-8000-000000000005' and state = 'installed') || '|' || (select count(*) from public.family_join_requests where requester_account_id = 'b0000000-0000-4000-8000-000000000005' and state = 'approved')"

echo 'family-code join-request race invariants passed'
