final class KeepersSchema {
  const KeepersSchema._();

  static const int version = 1;

  static const List<String> tableNames = [
    'families',
    'family_nfc_tags',
    'members',
    'devices',
    'entries',
    'entry_tags',
    'ceremonies',
    'ceremony_members',
    'keep_votes',
    'legacy_locks',
    'capsules',
    'draw_logs',
  ];

  static const List<String> versionOneStatements = [
    r'''
CREATE TABLE families (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  family_key_ref TEXT NOT NULL,
  quorum INTEGER NOT NULL CHECK (quorum > 0),
  created_at INTEGER NOT NULL
)
''',
    r'''
CREATE TABLE family_nfc_tags (
  family_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (family_id, tag_id),
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  role TEXT NOT NULL CHECK (role IN ('adult', 'child', 'elder')),
  birth_date INTEGER,
  memorial_state INTEGER NOT NULL DEFAULT 0
    CHECK (memorial_state IN (0, 1)),
  memorial_date INTEGER,
  created_at INTEGER NOT NULL,
  CHECK (memorial_state = 1 OR memorial_date IS NULL),
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  last_seen INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  entry_type TEXT NOT NULL
    CHECK (entry_type IN ('photo', 'voice', 'text', 'scan', 'recipe')),
  privacy_tier TEXT NOT NULL
    CHECK (privacy_tier IN ('journal', 'reveal', 'legacy')),
  blob_ref TEXT NOT NULL,
  transcript TEXT,
  embedding BLOB,
  state TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'revealed', 'kept', 'expired')),
  expires_at INTEGER,
  revealed_at INTEGER,
  kept_at INTEGER,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (author_id) REFERENCES members(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE entry_tags (
  entry_id TEXT NOT NULL,
  kind TEXT NOT NULL
    CHECK (kind IN ('theme', 'person', 'place', 'event')),
  value TEXT NOT NULL CHECK (length(trim(value)) > 0),
  PRIMARY KEY (entry_id, kind, value),
  FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE ceremonies (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  ceremony_date INTEGER NOT NULL,
  keeper_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'collecting'
    CHECK (status IN ('collecting', 'reel', 'keeping', 'closed', 'aborted')),
  reel_manifest TEXT NOT NULL DEFAULT '[]',
  closing_question_entry_id TEXT,
  created_at INTEGER NOT NULL,
  closed_at INTEGER,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (keeper_id) REFERENCES members(id) ON DELETE RESTRICT,
  FOREIGN KEY (closing_question_entry_id)
    REFERENCES entries(id) ON DELETE SET NULL
)
''',
    r'''
CREATE TABLE ceremony_members (
  ceremony_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  entry_count INTEGER NOT NULL DEFAULT 0 CHECK (entry_count >= 0),
  spectator_locked INTEGER NOT NULL DEFAULT 0
    CHECK (spectator_locked IN (0, 1)),
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (ceremony_id, member_id),
  FOREIGN KEY (ceremony_id) REFERENCES ceremonies(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE keep_votes (
  ceremony_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  vote INTEGER NOT NULL CHECK (vote IN (0, 1)),
  voted_at INTEGER NOT NULL,
  PRIMARY KEY (ceremony_id, entry_id, member_id),
  FOREIGN KEY (ceremony_id) REFERENCES ceremonies(id) ON DELETE CASCADE,
  FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE legacy_locks (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  target_id TEXT NOT NULL,
  content_entry_id TEXT NOT NULL,
  quest_description TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'locked'
    CHECK (state IN ('locked', 'submitted', 'approved')),
  proof_entry_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_id) REFERENCES members(id) ON DELETE RESTRICT,
  FOREIGN KEY (target_id) REFERENCES members(id) ON DELETE CASCADE,
  FOREIGN KEY (content_entry_id) REFERENCES entries(id) ON DELETE CASCADE,
  FOREIGN KEY (proof_entry_id) REFERENCES entries(id) ON DELETE SET NULL
)
''',
    r'''
CREATE TABLE capsules (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  target_id TEXT NOT NULL,
  content_entry_id TEXT NOT NULL,
  trigger_type TEXT NOT NULL
    CHECK (trigger_type IN ('date', 'milestone', 'shelf')),
  trigger_value TEXT,
  state TEXT NOT NULL DEFAULT 'locked'
    CHECK (state IN ('locked', 'ready', 'opened')),
  created_at INTEGER NOT NULL,
  opened_at INTEGER,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (author_id) REFERENCES members(id) ON DELETE RESTRICT,
  FOREIGN KEY (target_id) REFERENCES members(id) ON DELETE CASCADE,
  FOREIGN KEY (content_entry_id) REFERENCES entries(id) ON DELETE CASCADE
)
''',
    r'''
CREATE TABLE draw_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  shown_at INTEGER NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
)
''',
    'CREATE INDEX idx_members_family ON members(family_id)',
    'CREATE INDEX idx_devices_member ON devices(member_id)',
    'CREATE INDEX idx_entries_author_date '
        'ON entries(author_id, created_at DESC)',
    'CREATE INDEX idx_entries_family_state '
        'ON entries(family_id, privacy_tier, state, created_at DESC)',
    'CREATE INDEX idx_entries_expiry ON entries(state, expires_at)',
    'CREATE INDEX idx_entry_tags_lookup ON entry_tags(kind, value)',
    'CREATE INDEX idx_ceremonies_family_date '
        'ON ceremonies(family_id, ceremony_date DESC)',
    'CREATE INDEX idx_legacy_locks_target '
        'ON legacy_locks(target_id, state)',
    'CREATE INDEX idx_capsules_target ON capsules(target_id, state)',
    'CREATE INDEX idx_draw_logs_member_date '
        'ON draw_logs(member_id, shown_at DESC)',
  ];

  static List<String> statementsForUpgrade(
    int oldVersion,
    int newVersion,
  ) {
    if (oldVersion < 0 ||
        newVersion > version ||
        oldVersion >= newVersion) {
      throw ArgumentError(
        'Unsupported schema upgrade from $oldVersion to $newVersion',
      );
    }

    final statements = <String>[];
    if (oldVersion < 1 && newVersion >= 1) {
      statements.addAll(versionOneStatements);
    }

    return List.unmodifiable(statements);
  }
}
