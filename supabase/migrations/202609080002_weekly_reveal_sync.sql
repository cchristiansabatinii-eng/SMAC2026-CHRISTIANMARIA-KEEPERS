-- End-to-end encrypted Weekly Reveal relay.
--
-- Supabase sees only canonical routing metadata, integrity metadata, and the
-- opaque ciphertext object. Plaintext and family keys never enter this schema.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'keepers-weekly-reveal',
  'keepers-weekly-reveal',
  false,
  26214400,
  array['application/octet-stream']::pg_catalog.text[]
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.weekly_reveal_entries (
  id pg_catalog.uuid primary key,
  family_id pg_catalog.uuid not null,
  author_member_id pg_catalog.uuid not null,
  created_at pg_catalog.timestamptz not null,
  format pg_catalog.text not null,
  storage_path pg_catalog.text not null unique,
  blob_sha256 pg_catalog.text not null,
  blob_bytes pg_catalog.int8 not null,
  state pg_catalog.text not null default 'pending',
  published_at pg_catalog.timestamptz not null
    default pg_catalog.clock_timestamp(),
  constraint weekly_reveal_entries_author_membership_fkey
    foreign key (family_id, author_member_id)
    references public.family_memberships(family_id, member_id)
    on delete cascade,
  constraint weekly_reveal_entries_format_valid check (
    format in ('photo', 'voice', 'text')
  ),
  constraint weekly_reveal_entries_storage_path_valid check (
    storage_path = family_id::pg_catalog.text
      || '/'::pg_catalog.text
      || author_member_id::pg_catalog.text
      || '/'::pg_catalog.text
      || id::pg_catalog.text
      || '.keeper'::pg_catalog.text
  ),
  constraint weekly_reveal_entries_sha256_valid check (
    blob_sha256 ~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'
  ),
  constraint weekly_reveal_entries_blob_bytes_valid check (
    blob_bytes between 1 and 26214400
  ),
  constraint weekly_reveal_entries_state_valid check (state = 'pending'),
  constraint weekly_reveal_entries_timestamps_valid check (
    pg_catalog.isfinite(created_at)
    and pg_catalog.isfinite(published_at)
    and created_at <= published_at + '5 minutes'::pg_catalog.interval
  )
);

create index if not exists weekly_reveal_entries_family_created_idx
  on public.weekly_reveal_entries(family_id, created_at, id);

alter table public.weekly_reveal_entries enable row level security;
alter table public.weekly_reveal_entries replica identity full;

drop policy if exists "active family reads weekly reveal metadata"
  on public.weekly_reveal_entries;
create policy "active family reads weekly reveal metadata"
on public.weekly_reveal_entries
for select
to authenticated
using (private.is_active_family_member(family_id));

revoke all on table public.weekly_reveal_entries
  from public, anon, authenticated;
grant select on table public.weekly_reveal_entries to authenticated;

create or replace function private.is_canonical_weekly_reveal_path(
  p_storage_path pg_catalog.text
)
returns pg_catalog.bool
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_parts pg_catalog.text[];
  v_family_id pg_catalog.uuid;
  v_author_member_id pg_catalog.uuid;
  v_entry_id pg_catalog.uuid;
  v_entry_file pg_catalog.text;
begin
  if p_storage_path is null
    or pg_catalog.char_length(p_storage_path) > 128
  then
    return false;
  end if;

  v_parts := pg_catalog.string_to_array(p_storage_path, '/');
  if pg_catalog.array_length(v_parts, 1) <> 3 then
    return false;
  end if;

  v_entry_file := v_parts[3];
  if pg_catalog.right(v_entry_file, 7) <> '.keeper'
    or pg_catalog.char_length(v_entry_file) <> 43
  then
    return false;
  end if;

  v_family_id := v_parts[1]::pg_catalog.uuid;
  v_author_member_id := v_parts[2]::pg_catalog.uuid;
  v_entry_id := pg_catalog.left(v_entry_file, 36)::pg_catalog.uuid;

  return p_storage_path = v_family_id::pg_catalog.text
    || '/'::pg_catalog.text
    || v_author_member_id::pg_catalog.text
    || '/'::pg_catalog.text
    || v_entry_id::pg_catalog.text
    || '.keeper'::pg_catalog.text;
exception
  when others then return false;
end;
$function$;

create or replace function private.can_read_weekly_reveal_object(
  p_storage_path pg_catalog.text
)
returns pg_catalog.bool
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_family_id pg_catalog.uuid;
begin
  if not private.is_canonical_weekly_reveal_path(p_storage_path) then
    return false;
  end if;

  v_family_id := pg_catalog.split_part(p_storage_path, '/', 1)::pg_catalog.uuid;
  return private.is_active_family_member(v_family_id);
exception
  when others then return false;
end;
$function$;

create or replace function private.can_write_weekly_reveal_object(
  p_storage_path pg_catalog.text
)
returns pg_catalog.bool
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_family_id pg_catalog.uuid;
  v_author_member_id pg_catalog.uuid;
begin
  if v_account_id is null
    or not private.is_canonical_weekly_reveal_path(p_storage_path)
  then
    return false;
  end if;

  v_family_id := pg_catalog.split_part(p_storage_path, '/', 1)::pg_catalog.uuid;
  v_author_member_id := pg_catalog.split_part(p_storage_path, '/', 2)::pg_catalog.uuid;

  return exists (
    select 1
    from public.family_memberships as membership
    where membership.family_id = v_family_id
      and membership.account_id = v_account_id
      and membership.member_id = v_author_member_id
      and membership.state = 'active'
  );
exception
  when others then return false;
end;
$function$;

revoke all on function private.is_canonical_weekly_reveal_path(pg_catalog.text)
  from public, anon, authenticated;
revoke all on function private.can_read_weekly_reveal_object(pg_catalog.text)
  from public, anon, authenticated;
revoke all on function private.can_write_weekly_reveal_object(pg_catalog.text)
  from public, anon, authenticated;
grant execute on function private.can_read_weekly_reveal_object(pg_catalog.text)
  to authenticated;
grant execute on function private.can_write_weekly_reveal_object(pg_catalog.text)
  to authenticated;

drop policy if exists "weekly reveal: active family reads" on storage.objects;
create policy "weekly reveal: active family reads"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'keepers-weekly-reveal'
  and private.can_read_weekly_reveal_object(name)
);

drop policy if exists "weekly reveal: author inserts" on storage.objects;
create policy "weekly reveal: author inserts"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'keepers-weekly-reveal'
  and private.can_write_weekly_reveal_object(name)
);

drop policy if exists "weekly reveal: author upserts" on storage.objects;
create policy "weekly reveal: author upserts"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'keepers-weekly-reveal'
  and private.can_write_weekly_reveal_object(name)
)
with check (
  bucket_id = 'keepers-weekly-reveal'
  and private.can_write_weekly_reveal_object(name)
);

create or replace function private.weekly_reveal_entry_json(
  p_entry public.weekly_reveal_entries
)
returns pg_catalog.jsonb
language sql
stable
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'entryId', p_entry.id::pg_catalog.text,
    'familyId', p_entry.family_id::pg_catalog.text,
    'authorId', p_entry.author_member_id::pg_catalog.text,
    'createdAt', pg_catalog.to_jsonb(p_entry.created_at),
    'format', p_entry.format,
    'storagePath', p_entry.storage_path,
    'blobSha256', p_entry.blob_sha256,
    'blobBytes', p_entry.blob_bytes,
    'state', p_entry.state
  );
$function$;

revoke all on function private.weekly_reveal_entry_json(
  public.weekly_reveal_entries
) from public, anon, authenticated;

create or replace function public.publish_weekly_reveal_entry(
  p_entry_id pg_catalog.uuid,
  p_family_id pg_catalog.uuid,
  p_author_member_id pg_catalog.uuid,
  p_created_at pg_catalog.timestamptz,
  p_format pg_catalog.text,
  p_storage_path pg_catalog.text,
  p_blob_sha256 pg_catalog.text,
  p_blob_bytes pg_catalog.int8
)
returns pg_catalog.jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account_id pg_catalog.uuid := auth.uid();
  v_published_at pg_catalog.timestamptz := pg_catalog.clock_timestamp();
  v_expected_path pg_catalog.text;
  v_existing public.weekly_reveal_entries%rowtype;
  v_object_metadata pg_catalog.jsonb;
  v_object_user_metadata pg_catalog.jsonb;
  v_object_owner_id pg_catalog.text;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  v_expected_path := p_family_id::pg_catalog.text
    || '/'::pg_catalog.text
    || p_author_member_id::pg_catalog.text
    || '/'::pg_catalog.text
    || p_entry_id::pg_catalog.text
    || '.keeper'::pg_catalog.text;

  if p_entry_id is null
    or p_family_id is null
    or p_author_member_id is null
    or p_created_at is null
    or not pg_catalog.isfinite(p_created_at)
    or p_created_at > v_published_at + '5 minutes'::pg_catalog.interval
    or p_format is null
    or p_format not in ('photo', 'voice', 'text')
    or p_storage_path is null
    or p_storage_path <> v_expected_path
    or not private.is_canonical_weekly_reveal_path(p_storage_path)
    or p_blob_sha256 is null
    or p_blob_sha256 !~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'
    or p_blob_bytes is null
    or p_blob_bytes not between 1 and 26214400
  then
    raise exception using errcode = 'P0001', message = 'INVALID_REVEAL_ENTRY';
  end if;

  if not exists (
    select 1
    from public.family_memberships as membership
    where membership.family_id = p_family_id
      and membership.account_id = v_account_id
      and membership.member_id = p_author_member_id
      and membership.state = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'FORBIDDEN';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'keepers.publish_weekly_reveal_entry.v1:'::pg_catalog.text
        || p_entry_id::pg_catalog.text,
      0::pg_catalog.int8
    )
  );

  select entry.*
  into v_existing
  from public.weekly_reveal_entries as entry
  where entry.id = p_entry_id
    or entry.storage_path = p_storage_path
  order by (entry.id = p_entry_id) desc
  limit 1
  for update;

  if found and (
    v_existing.id <> p_entry_id
    or v_existing.family_id <> p_family_id
    or v_existing.author_member_id <> p_author_member_id
    or v_existing.created_at <> p_created_at
    or v_existing.format <> p_format
    or v_existing.storage_path <> p_storage_path
    or v_existing.blob_sha256 <> p_blob_sha256
    or v_existing.blob_bytes <> p_blob_bytes
    or v_existing.state <> 'pending'
  ) then
    raise exception using errcode = 'P0001', message = 'ENTRY_CONFLICT';
  end if;

  select object.metadata, object.user_metadata, object.owner_id
  into v_object_metadata, v_object_user_metadata, v_object_owner_id
  from storage.objects as object
  where object.bucket_id = 'keepers-weekly-reveal'
    and object.name = p_storage_path;

  if not found then
    raise exception using errcode = 'P0001', message = 'OBJECT_NOT_FOUND';
  end if;

  if v_object_owner_id is distinct from v_account_id::pg_catalog.text
    or v_object_metadata ->> 'size' is distinct from p_blob_bytes::pg_catalog.text
    or v_object_metadata ->> 'mimetype' is distinct from 'application/octet-stream'
    or v_object_user_metadata ->> 'sha256' is distinct from p_blob_sha256
  then
    raise exception using errcode = 'P0001', message = 'OBJECT_MISMATCH';
  end if;

  if v_existing.id is not null then
    return private.weekly_reveal_entry_json(v_existing);
  end if;

  insert into public.weekly_reveal_entries (
    id,
    family_id,
    author_member_id,
    created_at,
    format,
    storage_path,
    blob_sha256,
    blob_bytes,
    state,
    published_at
  )
  values (
    p_entry_id,
    p_family_id,
    p_author_member_id,
    p_created_at,
    p_format,
    p_storage_path,
    p_blob_sha256,
    p_blob_bytes,
    'pending',
    v_published_at
  )
  returning * into v_existing;

  return private.weekly_reveal_entry_json(v_existing);
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'ENTRY_CONFLICT';
end;
$function$;

create or replace function public.list_weekly_reveal_entries(
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
  v_result pg_catalog.jsonb;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;

  if p_family_id is null then
    raise exception using errcode = 'P0001', message = 'INVALID_REVEAL_ENTRY';
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

  select coalesce(
    pg_catalog.jsonb_agg(
      private.weekly_reveal_entry_json(entry)
      order by entry.created_at, entry.id
    ),
    '[]'::pg_catalog.jsonb
  )
  into v_result
  from public.weekly_reveal_entries as entry
  where entry.family_id = p_family_id
    and entry.state = 'pending';

  return v_result;
end;
$function$;

revoke all on function public.publish_weekly_reveal_entry(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int8
) from public, anon, authenticated;
grant execute on function public.publish_weekly_reveal_entry(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.text,
  pg_catalog.int8
) to authenticated;

revoke all on function public.list_weekly_reveal_entries(pg_catalog.uuid)
  from public, anon, authenticated;
grant execute on function public.list_weekly_reveal_entries(pg_catalog.uuid)
  to authenticated;

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
      and tablename = 'weekly_reveal_entries'
  ) then
    alter publication supabase_realtime
      add table public.weekly_reveal_entries;
  end if;
end;
$publication$;
