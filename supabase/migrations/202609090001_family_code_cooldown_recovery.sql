-- PostgreSQL implements LEAST as SQL syntax, not as a schema-qualified
-- pg_catalog function. Repair only the invalid cooldown expression while
-- preserving the routine's signature, ownership, grants, and security-definer
-- configuration.
do $repair$
declare
  v_signature pg_catalog.regprocedure :=
    'private.record_invalid_family_code_attempt(uuid)'::pg_catalog.regprocedure;
  v_definition pg_catalog.text;
begin
  select pg_catalog.pg_get_functiondef(v_signature::pg_catalog.oid)
  into v_definition;

  if pg_catalog.strpos(v_definition, 'pg_catalog.least(') > 0 then
    execute pg_catalog.replace(
      v_definition,
      'pg_catalog.least(',
      'least('
    );
  end if;

  select pg_catalog.pg_get_functiondef(v_signature::pg_catalog.oid)
  into v_definition;

  if pg_catalog.strpos(v_definition, 'pg_catalog.least(') > 0 then
    raise exception 'failed to repair private.record_invalid_family_code_attempt(uuid)';
  end if;
end;
$repair$;
