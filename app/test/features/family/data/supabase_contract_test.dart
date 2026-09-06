import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    '../supabase/migrations/202609050001_family_invitations.sql',
  );
  final recoveryMigration = File(
    '../supabase/migrations/202609080001_family_code_bootstrap_recovery.sql',
  );
  final cooldownRecoveryMigration = File(
    '../supabase/migrations/202609090001_family_code_cooldown_recovery.sql',
  );
  final config = File('../supabase/config.toml');
  final readme = File('../supabase/README.md');
  final pgTap = File('../supabase/tests/family_invitations_test.sql');
  late String sql;
  late String recoverySql;
  late String cooldownRecoverySql;
  late String configText;
  late String readmeText;
  late String pgTapText;

  setUpAll(() {
    sql = migration.existsSync() ? migration.readAsStringSync() : '';
    recoverySql = recoveryMigration.existsSync()
        ? recoveryMigration.readAsStringSync()
        : '';
    cooldownRecoverySql = cooldownRecoveryMigration.existsSync()
        ? cooldownRecoveryMigration.readAsStringSync()
        : '';
    configText = config.existsSync() ? config.readAsStringSync() : '';
    readmeText = readme.existsSync() ? readme.readAsStringSync() : '';
    pgTapText = pgTap.existsSync() ? pgTap.readAsStringSync() : '';
  });

  test('family invitation migration exists', () {
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'The versioned Supabase migration must ship with the app.',
    );
  });

  test('deployed family-code recovery migration repairs exact routines', () {
    expect(recoveryMigration.existsSync(), isTrue);
    expect(recoverySql, contains('pg_catalog.pg_get_functiondef'));
    expect(recoverySql, contains("'pg_catalog.coalesce('"));
    expect(recoverySql, contains("'coalesce('"));
    for (final signature in <String>[
      'public.bootstrap_owner_family(uuid,text,uuid,text,text,text,jsonb)',
      'public.create_family_invite(uuid,uuid,text,text,jsonb)',
      'public.preview_family_invite(text)',
      'public.claim_family_invite(text,uuid,text,text,text,jsonb)',
      'public.list_active_family_members(uuid)',
      'private.own_family_join_request_json(public.family_join_requests)',
      'public.preview_family_by_code(text)',
      'public.create_family_join_request(uuid,text,uuid,text,text,text,jsonb,text)',
      'public.list_pending_family_join_requests(uuid)',
    ]) {
      expect(recoverySql, contains("'$signature'::pg_catalog.regprocedure"));
    }
    expect(
      recoverySql,
      contains('create or replace function public.get_family_join_code'),
    );
    expect(
      recoverySql,
      contains('or not private.is_active_family_member(p_family_id)'),
    );
  });

  test('cooldown recovery migration repairs only the invalid LEAST call', () {
    expect(cooldownRecoveryMigration.existsSync(), isTrue);
    expect(cooldownRecoverySql, contains('pg_catalog.pg_get_functiondef'));
    expect(
      cooldownRecoverySql,
      contains('private.record_invalid_family_code_attempt(uuid)'),
    );
    expect(cooldownRecoverySql, contains("'pg_catalog.least('"));
    expect(cooldownRecoverySql, contains("'least('"));
    expect(
      cooldownRecoverySql,
      contains('failed to repair private.record_invalid_family_code_attempt'),
    );
  });

  test('migration declares each cloud table exactly once', () {
    for (final table in <String>[
      'profiles',
      'cloud_families',
      'family_memberships',
      'family_invites',
    ]) {
      _expectExactlyOnce(
        sql,
        RegExp(
          r'create\s+table\s+if\s+not\s+exists\s+public\.'
          '$table'
          r'\b',
          caseSensitive: false,
        ),
        'table public.$table',
      );
    }
  });

  test('migration declares each public RPC exactly once', () {
    for (final function in _rpcNames) {
      _expectExactlyOnce(
        sql,
        RegExp(
          r'create\s+or\s+replace\s+function\s+public\.'
          '$function'
          r'\s*\(',
          caseSensitive: false,
        ),
        'function public.$function',
      );
    }
  });

  test('all exposed tables enable row level security exactly once', () {
    for (final table in <String>[
      'profiles',
      'cloud_families',
      'family_memberships',
      'family_invites',
    ]) {
      _expectExactlyOnce(
        sql,
        RegExp(
          r'alter\s+table\s+public\.'
          '$table'
          r'\s+enable\s+row\s+level\s+security\s*;',
          caseSensitive: false,
        ),
        'RLS enablement for public.$table',
      );
    }
  });

  test('every RPC is security definer with an empty search path', () {
    for (final function in _rpcNames) {
      final definition = _functionDefinition(sql, function);
      _expectExactlyOnce(
        definition,
        RegExp(r'\bsecurity\s+definer\b', caseSensitive: false),
        'security definer on $function',
      );
      _expectExactlyOnce(
        definition,
        RegExp(r"\bset\s+search_path\s*=\s*''\s*\r?\n", caseSensitive: false),
        'empty search_path on $function',
      );
      for (final builtIn in _securityDefinerBuiltIns) {
        expect(
          definition,
          isNot(
            contains(
              RegExp(
                '(^|[^.\\w])$builtIn\\s*\\(',
                caseSensitive: false,
                multiLine: true,
              ),
            ),
          ),
          reason: '$function must schema-qualify $builtIn',
        );
      }
    }

    final helper = _functionDefinition(
      sql,
      'is_active_family_member',
      schema: 'private',
    );
    _expectExactlyOnce(
      helper,
      RegExp(r"\bset\s+search_path\s*=\s*''\s*\r?\n", caseSensitive: false),
      'empty search_path on private.is_active_family_member',
    );
  });

  test('conditional COALESCE expressions are never schema-qualified', () {
    expect(
      sql,
      isNot(
        contains(RegExp(r'pg_catalog\.coalesce\s*\(', caseSensitive: false)),
      ),
      reason: 'COALESCE is PostgreSQL syntax, not a function that can be schema-qualified.',
    );
  });

  test('owner mutations require an active owner membership', () {
    for (final function in <String>[
      'create_family_invite',
      'revoke_family_invite',
    ]) {
      final definition = _functionDefinition(sql, function);
      _expectExactlyOnce(
        definition,
        RegExp(
          r"membership_role\s*=\s*'owner'[^;]+state\s*=\s*'active'",
          caseSensitive: false,
          dotAll: true,
        ),
        'active owner membership check in $function',
      );
      _expectExactlyOnce(
        definition,
        RegExp(r'owner_account_id\s*=\s*v_account_id', caseSensitive: false),
        'original owner check in $function',
      );
    }
  });

  test('token and recipient checks hash canonical values', () {
    final create = _functionDefinition(sql, 'create_family_invite');
    _expectExactlyOnce(
      create,
      RegExp(
        r"extensions\.digest\s*\(\s*v_recipient_email\s*,\s*'sha256'\s*\)",
        caseSensitive: false,
      ),
      'normalized recipient email hashing',
    );

    for (final function in <String>[
      'preview_family_invite',
      'claim_family_invite',
    ]) {
      final definition = _functionDefinition(sql, function);
      _expectExactlyOnce(
        definition,
        RegExp(
          r"extensions\.digest\s*\(\s*pg_catalog\.decode\s*\([^;]+\)\s*,\s*'sha256'\s*\)",
          caseSensitive: false,
          dotAll: true,
        ),
        'decoded token hashing in $function',
      );
      _expectExactlyOnce(
        definition,
        RegExp(
          r"recipient_email_hash\s*<>\s*extensions\.digest\s*\(\s*v_email\s*,\s*'sha256'\s*\)",
          caseSensitive: false,
        ),
        'JWT email binding in $function',
      );
    }
  });

  test('pending claims enforce 24-hour expiry using wall-clock time', () {
    final create = _functionDefinition(sql, 'create_family_invite');
    _expectExactlyOnce(
      create,
      RegExp(
        r"v_now\s*\+\s*'24\s+hours'::pg_catalog\.interval",
        caseSensitive: false,
      ),
      '24-hour server expiry',
    );

    for (final function in <String>[
      'preview_family_invite',
      'claim_family_invite',
    ]) {
      final definition = _functionDefinition(sql, function);
      _expectExactlyOnce(
        definition,
        RegExp(
          r'clock_timestamp\s*\(\s*\)\s*>=\s*v_invite\.expires_at',
          caseSensitive: false,
        ),
        'wall-clock expiry check in $function',
      );
    }
  });

  test('invitation state mutations lock exactly one row', () {
    for (final function in <String>[
      'claim_family_invite',
      'complete_family_invite',
      'revoke_family_invite',
    ]) {
      _expectExactlyOnce(
        _functionDefinition(sql, function),
        RegExp(r'\bfor\s+update\s*;', caseSensitive: false),
        'row lock in $function',
      );
    }
  });

  test('direct mutations and implicit function execution are revoked', () {
    _expectExactlyOnce(
      sql,
      RegExp(
        r'revoke\s+insert\s*,\s*update\s*,\s*delete\s*,\s*truncate\s+on\s+'
        r'public\.profiles\s*,\s*public\.cloud_families\s*,\s*'
        r'public\.family_memberships\s*,\s*public\.family_invites\s+'
        r'from\s+anon\s*,\s*authenticated\s*;',
        caseSensitive: false,
      ),
      'direct table mutation revoke',
    );

    for (final function in _rpcNames) {
      final signature = RegExp.escape('public.$function');
      _expectExactlyOnce(
        sql,
        RegExp(
          'revoke\\s+execute\\s+on\\s+function\\s+$signature\\s*\\([^;]+?'
          r'\)\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;',
          caseSensitive: false,
        ),
        'implicit execute revoke for $function',
      );
      _expectExactlyOnce(
        sql,
        RegExp(
          'grant\\s+execute\\s+on\\s+function\\s+$signature\\s*\\([^;]+?'
          r'\)\s+to\s+authenticated\s*;',
          caseSensitive: false,
        ),
        'authenticated execute grant for $function',
      );
    }
  });

  test('membership internals cannot be selected directly', () {
    expect(
      sql,
      isNot(
        contains(
          RegExp(
            r'grant\s+select\s+on\s+public\.family_memberships\s+to\s+'
            r'authenticated\s*;',
            caseSensitive: false,
          ),
        ),
      ),
    );
    _expectExactlyOnce(
      sql,
      RegExp(
        r'revoke\s+all\s+on\s+public\.family_memberships\s+from\s+'
        r'public\s*,\s*anon\s*,\s*authenticated\s*;',
        caseSensitive: false,
      ),
      'direct family_memberships access revoke',
    );
  });

  test('revocation is pending-only and never rolls back a claim', () {
    final definition = _functionDefinition(sql, 'revoke_family_invite');
    expect(
      definition,
      contains(
        RegExp(
          r"if\s+v_invite\.state\s*=\s*'claimed'\s+then\s+raise\s+exception"
          r"[^;]+message\s*=\s*'ALREADY_CLAIMED'",
          caseSensitive: false,
          dotAll: true,
        ),
      ),
    );
    expect(
      definition,
      contains(
        RegExp(
          r"where\s+id\s*=\s*v_invite\.id\s+and\s+state\s*=\s*'pending'",
          caseSensitive: false,
        ),
      ),
    );
    expect(
      definition,
      isNot(
        contains(
          RegExp(
            r'delete\s+from\s+public\.family_memberships',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('bootstrap rejects a mismatched replay before profile mutation', () {
    final definition = _functionDefinition(sql, 'bootstrap_owner_family');
    expect(
      definition,
      contains(
        RegExp(
          r'v_family\.name\s+is\s+distinct\s+from\s+p_family_name',
          caseSensitive: false,
        ),
      ),
      reason: 'bootstrap replay must compare family name',
    );
    for (final field in <String>[
      'member_id',
      'display_name',
      'demographic_role',
      'color_token',
      'avatar_json',
      'membership_role',
      'state',
    ]) {
      expect(
        definition,
        contains(
          RegExp(
            'v_membership\\.$field\\s+is\\s+distinct\\s+from',
            caseSensitive: false,
          ),
        ),
        reason: 'bootstrap replay must compare $field',
      );
    }

    final replayGuard = definition.indexOf("message = 'BOOTSTRAP_CONFLICT'");
    final profileMutation = definition.indexOf('insert into public.profiles');
    expect(replayGuard, greaterThanOrEqualTo(0));
    expect(profileMutation, greaterThan(replayGuard));
  });

  test('bootstrap serializes the absent-membership first-call path', () {
    final definition = _functionDefinition(sql, 'bootstrap_owner_family');
    _expectExactlyOnce(
      definition,
      RegExp(
        r'perform\s+pg_catalog\.pg_advisory_xact_lock\s*\(\s*'
        r'pg_catalog\.hashtextextended\s*\(\s*'
        r"'keepers\.bootstrap_owner_family\.v1:'::pg_catalog\.text\s*\|\|\s*"
        r'v_account_id::pg_catalog\.text\s*,\s*0::pg_catalog\.int8\s*\)\s*\)\s*;',
        caseSensitive: false,
      ),
      'full-account transaction lock',
    );

    final lock = definition.indexOf('pg_catalog.pg_advisory_xact_lock');
    final membershipProbe = definition.indexOf('select membership.*');
    final profileMutation = definition.indexOf('insert into public.profiles');
    expect(lock, greaterThanOrEqualTo(0));
    expect(membershipProbe, greaterThan(lock));
    expect(profileMutation, greaterThan(membershipProbe));
  });

  test('migration schema-qualifies every built-in data type', () {
    for (final type in _builtInDataTypes) {
      expect(
        sql,
        isNot(
          contains(
            RegExp(
              '(^|[^.\\w])$type\\b',
              caseSensitive: false,
              multiLine: true,
            ),
          ),
        ),
        reason: '$type must be qualified through pg_catalog',
      );
    }
  });

  test('Supabase package has safe config and ordered local workflow', () {
    expect(config.existsSync(), isTrue);
    expect(
      configText,
      contains(RegExp(r'^project_id\s*=\s*"[^"]+"', multiLine: true)),
    );
    expect(
      configText,
      contains(RegExp(r'^\[db\.migrations\]$', multiLine: true)),
    );
    expect(
      configText,
      contains(RegExp(r'^major_version\s*=\s*17$', multiLine: true)),
    );
    expect(
      configText,
      contains(
        RegExp(r'^\[db\.seed\]\s*\r?\nenabled\s*=\s*false$', multiLine: true),
      ),
    );
    expect(
      configText,
      isNot(
        contains(
          RegExp(
            r'(service_role|anon_key|jwt_secret|database_password)\s*=',
            caseSensitive: false,
          ),
        ),
      ),
    );

    final start = readmeText.indexOf('supabase start');
    final reset = readmeText.indexOf('supabase db reset --local');
    final test = readmeText.indexOf('supabase test db --local');
    expect(start, greaterThanOrEqualTo(0));
    expect(reset, greaterThan(start));
    expect(test, greaterThan(reset));
  });

  test('pgTAP suite pins its plan and exercises client-role boundaries', () {
    expect(pgTap.existsSync(), isTrue);
    final assertions = RegExp(
      r'^select\s+(?:has_table|has_function|policies_are|is\(|ok\(|lives_ok\(|throws_ok\()',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(pgTapText).length;
    final plan = RegExp(
      r'^select\s+plan\((\d+)\);',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(pgTapText);
    expect(plan, isNotNull);
    expect(int.parse(plan!.group(1)!), assertions);
    expect(pgTapText, contains('pg_catalog.has_function_privilege'));
    expect(
      pgTapText,
      contains('public.preview_family_invite(pg_catalog.text)'),
    );
    expect(pgTapText, isNot(contains('set local role anon;')));
    expect(
      RegExp(
        r'set\s+local\s+role\s+authenticated\s*;',
        caseSensitive: false,
      ).allMatches(pgTapText).length,
      greaterThanOrEqualTo(10),
    );
    expect(
      pgTapText,
      contains(
        RegExp(r'expires_at\s*=\s*test_clock\.now', caseSensitive: false),
      ),
    );
    expect(pgTapText, contains("'ALREADY_CLAIMED'"));
    expect(
      pgTapText,
      contains('permission denied for table family_memberships'),
    );
    expect(pgTapText, contains('pg_catalog.jsonb_object_keys'));
  });

  test('migration stores only hashes and the exact encrypted envelope', () {
    final invites = _tableDefinition(sql, 'family_invites');
    expect(invites, contains(RegExp(r'\btoken_hash\s+pg_catalog\.text\b')));
    expect(
      invites,
      contains(RegExp(r'\brecipient_email_hash\s+pg_catalog\.bytea\b')),
    );
    expect(
      invites,
      isNot(
        contains(
          RegExp(
            r'\b(token|recipient_email|wrapping_secret|family_key|member_key|memory_payload)\s+',
            caseSensitive: false,
          ),
        ),
      ),
    );

    final create = _functionDefinition(sql, 'create_family_invite');
    expect(
      create,
      contains(
        RegExp(
          r"p_envelope\s*-\s*array\s*\[\s*'version'\s*,\s*'inviteId'\s*,\s*'familyId'\s*,\s*'nonce'\s*,\s*'ciphertext'\s*,\s*'mac'\s*\]",
          caseSensitive: false,
        ),
      ),
    );
  });

  test('nullable profile and envelope inputs fail before mutation', () {
    for (final function in <String>[
      'bootstrap_owner_family',
      'claim_family_invite',
    ]) {
      final definition = _functionDefinition(sql, function);
      _expectExactlyOnce(
        definition,
        RegExp(r'\bp_avatar_json\s+is\s+null\b', caseSensitive: false),
        'null avatar rejection in $function',
      );
      _expectExactlyOnce(
        definition,
        RegExp(r'\bp_demographic_role\s+is\s+null\b', caseSensitive: false),
        'null demographic role rejection in $function',
      );
    }

    _expectExactlyOnce(
      _functionDefinition(sql, 'create_family_invite'),
      RegExp(r'\bp_envelope\s+is\s+null\b', caseSensitive: false),
      'null envelope rejection in create_family_invite',
    );
  });

  test('profile avatars use the exact versioned Humation contract', () {
    final helper = _functionDefinition(
      sql,
      'is_valid_avatar_json',
      schema: 'private',
    );
    expect(helper, contains("'schemaVersion'"));
    expect(helper, contains("'humation-1'"));
    expect(helper, contains("'styleRevision'"));
    expect(helper, contains("'selections'"));
    expect(helper, contains("'colors'"));
    expect(helper, contains('hm1-p-000001'));
    expect(helper, contains('hm1-p-000086'));
    expect(
      helper,
      contains(
        RegExp(
          r"v_key\s+not\s+in\s*\(\s*'hair'\s*,\s*'skin'\s*,\s*'clothes'\s*,\s*'bottom'\s*\)",
          caseSensitive: false,
        ),
      ),
    );
    expect(
      helper,
      contains(
        RegExp(r"v_text\s*!~\s*'\^\[0-9a-f\]\{6\}\$'", caseSensitive: true),
      ),
    );

    final memberships = _tableDefinition(sql, 'family_memberships');
    expect(
      memberships,
      contains(
        RegExp(
          r'private\.is_valid_avatar_json\s*\(\s*avatar_json\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    for (final function in <String>[
      'bootstrap_owner_family',
      'claim_family_invite',
    ]) {
      expect(
        _functionDefinition(sql, function),
        contains(
          RegExp(
            r'not\s+private\.is_valid_avatar_json\s*\(\s*p_avatar_json\s*\)',
            caseSensitive: false,
          ),
        ),
      );
    }

    expect(pgTapText, contains('bootstrap rejects an empty avatar object'));
    expect(pgTapText, contains('bootstrap rejects an unknown avatar part'));
    expect(
      pgTapText,
      contains('claim accepts a canonical custom avatar color'),
    );
    expect(pgTapText, contains('claim rejects an unknown avatar color slot'));
    expect(pgTapText, contains('claim rejects a non-canonical avatar color'));
    expect(pgTapText, contains('claim rejects an oversized avatar seed'));
  });
}

const _rpcNames = <String>[
  'bootstrap_owner_family',
  'create_family_invite',
  'preview_family_invite',
  'claim_family_invite',
  'complete_family_invite',
  'revoke_family_invite',
  'list_active_family_members',
];

const _securityDefinerBuiltIns = <String>[
  'btrim',
  'char_length',
  'clock_timestamp',
  'decode',
  'encode',
  'jsonb_agg',
  'jsonb_build_object',
  'jsonb_typeof',
  'lower',
  'octet_length',
  'rtrim',
  'translate',
];

const _builtInDataTypes = <String>[
  'bigint',
  'bool',
  'boolean',
  'bytea',
  'int2',
  'int4',
  'int8',
  'integer',
  'interval',
  'jsonb',
  'smallint',
  'text',
  'timestamptz',
  'uuid',
];

void _expectExactlyOnce(String source, RegExp pattern, String description) {
  expect(
    pattern.allMatches(source),
    hasLength(1),
    reason: '$description must be present exactly once.',
  );
}

String _functionDefinition(
  String source,
  String function, {
  String schema = 'public',
}) {
  final matches = RegExp(
    r'create\s+or\s+replace\s+function\s+'
    '$schema\\.'
    '$function'
    r'\s*\([\s\S]*?\$function\$\s*;',
    caseSensitive: false,
  ).allMatches(source).toList(growable: false);
  expect(
    matches,
    hasLength(1),
    reason: 'Expected one complete definition for $schema.$function.',
  );
  return matches.single.group(0)!;
}

String _tableDefinition(String source, String table) {
  final matches = RegExp(
    r'create\s+table\s+if\s+not\s+exists\s+public\.'
    '$table'
    r'\s*\([\s\S]*?\n\);',
    caseSensitive: false,
  ).allMatches(source).toList(growable: false);
  expect(
    matches,
    hasLength(1),
    reason: 'Expected one complete definition for public.$table.',
  );
  return matches.single.group(0)!;
}
