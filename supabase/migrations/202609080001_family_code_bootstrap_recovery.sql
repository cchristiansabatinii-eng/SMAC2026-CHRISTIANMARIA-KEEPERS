-- PostgreSQL implements COALESCE as SQL syntax, not as a schema-qualified
-- pg_catalog function. Repair the exact routines shipped by the two family
-- migrations without changing their signatures, ownership, grants, or
-- security-definer configuration.
do $repair$
declare
  v_signature pg_catalog.regprocedure;
  v_definition pg_catalog.text;
begin
  foreach v_signature in array array[
    'public.bootstrap_owner_family(uuid,text,uuid,text,text,text,jsonb)'::pg_catalog.regprocedure,
    'public.create_family_invite(uuid,uuid,text,text,jsonb)'::pg_catalog.regprocedure,
    'public.preview_family_invite(text)'::pg_catalog.regprocedure,
    'public.claim_family_invite(text,uuid,text,text,text,jsonb)'::pg_catalog.regprocedure,
    'public.list_active_family_members(uuid)'::pg_catalog.regprocedure,
    'private.own_family_join_request_json(public.family_join_requests)'::pg_catalog.regprocedure,
    'public.preview_family_by_code(text)'::pg_catalog.regprocedure,
    'public.create_family_join_request(uuid,text,uuid,text,text,text,jsonb,text)'::pg_catalog.regprocedure,
    'public.list_pending_family_join_requests(uuid)'::pg_catalog.regprocedure
  ]
  loop
    select pg_catalog.pg_get_functiondef(v_signature::pg_catalog.oid)
    into v_definition;

    if pg_catalog.strpos(v_definition, 'pg_catalog.coalesce(') > 0 then
      execute pg_catalog.replace(
        v_definition,
        'pg_catalog.coalesce(',
        'coalesce('
      );
    end if;
  end loop;
end;
$repair$;

-- Preserve the membership-first lookup contract. A locally bound owner can
-- safely attempt the idempotent bootstrap after FORBIDDEN; the bootstrap RPC
-- still proves ownership server-side and prevents a family-existence oracle.
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
