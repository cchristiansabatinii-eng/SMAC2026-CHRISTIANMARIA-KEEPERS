-- family_memberships originally evaluated three volatile wall-clock defaults
-- independently. Because joined_at is declared before created_at, an insert
-- that omits both values could violate joined_at >= created_at. Use one
-- statement-stable instant for every omitted membership timestamp.
alter table public.family_memberships
  alter column joined_at set default pg_catalog.statement_timestamp(),
  alter column created_at set default pg_catalog.statement_timestamp(),
  alter column updated_at set default pg_catalog.statement_timestamp();
