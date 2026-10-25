PRAGMA foreign_keys = ON;
CREATE TABLE users (
 id TEXT PRIMARY KEY, google_sub TEXT NOT NULL UNIQUE,
 email TEXT NOT NULL, email_hash TEXT NOT NULL, name TEXT NOT NULL,
 created_at INTEGER NOT NULL, deleted_at INTEGER
) STRICT;
CREATE TABLE families (
 id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
 created_at INTEGER NOT NULL, deleted_at INTEGER
) STRICT;
CREATE TABLE members (
 family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('owner','editor','viewer')),
 status TEXT NOT NULL CHECK(status IN ('active','pending','suspended')), invitation_id TEXT,
 PRIMARY KEY(family_id,user_id)
) STRICT;
CREATE UNIQUE INDEX one_active_family ON members(user_id) WHERE status='active';
CREATE TRIGGER protect_last_owner_update BEFORE UPDATE ON members
WHEN OLD.role='owner' AND OLD.status='active' AND (NEW.role<>'owner' OR NEW.status<>'active')
AND EXISTS(SELECT 1 FROM families WHERE id=OLD.family_id AND deleted_at IS NULL)
AND (SELECT count(*) FROM members WHERE family_id=OLD.family_id AND role='owner' AND status='active')<=1
BEGIN SELECT RAISE(ABORT,'LAST_OWNER_REQUIRED'); END;
CREATE TRIGGER protect_last_owner_delete BEFORE DELETE ON members
WHEN OLD.role='owner' AND OLD.status='active'
AND EXISTS(SELECT 1 FROM families WHERE id=OLD.family_id AND deleted_at IS NULL)
AND (SELECT count(*) FROM members WHERE family_id=OLD.family_id AND role='owner' AND status='active')<=1
BEGIN SELECT RAISE(ABORT,'LAST_OWNER_REQUIRED'); END;
CREATE TABLE sessions (
 token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 expires_at INTEGER NOT NULL, authenticated_at INTEGER NOT NULL
) STRICT;
CREATE INDEX sessions_expiry ON sessions(expires_at);
CREATE TABLE auth_flows (
 state_hash TEXT PRIMARY KEY, nonce TEXT NOT NULL, google_verifier TEXT NOT NULL,
 challenge TEXT NOT NULL, return_to TEXT NOT NULL, expires_at INTEGER NOT NULL
) STRICT;
CREATE TABLE login_tickets (
 ticket_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 challenge TEXT NOT NULL, expires_at INTEGER NOT NULL, used_at INTEGER
) STRICT;
CREATE TABLE records (
 family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN ('person','relationship','place','event')),
 id TEXT NOT NULL, data TEXT NOT NULL CHECK(json_valid(data)),
 version INTEGER NOT NULL CHECK(version>0), created_at INTEGER NOT NULL,
 updated_at INTEGER NOT NULL, deleted_at INTEGER,
 PRIMARY KEY(family_id,kind,id)
) STRICT;
CREATE INDEX records_live ON records(family_id,kind,updated_at) WHERE deleted_at IS NULL;
CREATE TRIGGER relationship_cycle_insert BEFORE INSERT ON records
WHEN NEW.kind='relationship' AND json_extract(NEW.data,'$.kind') IN ('parentChild','adoptedParentChild','stepParentChild')
BEGIN
 SELECT RAISE(ABORT,'PARENT_CYCLE') WHERE EXISTS(
  WITH RECURSIVE descendants(id) AS (
   SELECT json_extract(NEW.data,'$.toPersonId')
   UNION
   SELECT json_extract(r.data,'$.toPersonId') FROM records r JOIN descendants d ON json_extract(r.data,'$.fromPersonId')=d.id
   WHERE r.family_id=NEW.family_id AND r.kind='relationship' AND r.deleted_at IS NULL AND r.id<>NEW.id
   AND json_extract(r.data,'$.kind') IN ('parentChild','adoptedParentChild','stepParentChild')
  ) SELECT 1 FROM descendants WHERE id=json_extract(NEW.data,'$.fromPersonId')
 );
END;
CREATE TRIGGER relationship_cycle_update BEFORE UPDATE OF data ON records
WHEN NEW.kind='relationship' AND json_extract(NEW.data,'$.kind') IN ('parentChild','adoptedParentChild','stepParentChild')
BEGIN
 SELECT RAISE(ABORT,'PARENT_CYCLE') WHERE EXISTS(
  WITH RECURSIVE descendants(id) AS (
   SELECT json_extract(NEW.data,'$.toPersonId')
   UNION
   SELECT json_extract(r.data,'$.toPersonId') FROM records r JOIN descendants d ON json_extract(r.data,'$.fromPersonId')=d.id
   WHERE r.family_id=NEW.family_id AND r.kind='relationship' AND r.deleted_at IS NULL AND r.id<>NEW.id
   AND json_extract(r.data,'$.kind') IN ('parentChild','adoptedParentChild','stepParentChild')
  ) SELECT 1 FROM descendants WHERE id=json_extract(NEW.data,'$.fromPersonId')
 );
END;
CREATE TABLE preferences (
 family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 center_person_id TEXT NOT NULL DEFAULT '', PRIMARY KEY(family_id,user_id)
) STRICT;
CREATE TABLE invitations (
 id TEXT PRIMARY KEY, family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL UNIQUE, code_hash TEXT NOT NULL UNIQUE, email_hash TEXT NOT NULL,
 role TEXT NOT NULL CHECK(role IN ('editor','viewer')),
 status TEXT NOT NULL CHECK(status IN ('active','accepted','approved','revoked')),
 expires_at INTEGER NOT NULL, accepted_by TEXT REFERENCES users(id) ON DELETE SET NULL,
 accepted_name TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX invitations_family ON invitations(family_id,status);
CREATE TRIGGER invitation_approval_guard BEFORE UPDATE OF status ON invitations
WHEN NEW.status='approved' AND OLD.status='accepted'
BEGIN
 SELECT RAISE(ABORT,'INVITATION_INVALID') WHERE NOT EXISTS(
  SELECT 1 FROM members m JOIN users u ON u.id=m.user_id JOIN families f ON f.id=m.family_id
  WHERE m.family_id=NEW.family_id AND m.user_id=NEW.accepted_by AND m.status='pending'
  AND m.invitation_id=NEW.id AND u.deleted_at IS NULL AND f.deleted_at IS NULL
 );
END;
CREATE TABLE attachments (
 id TEXT PRIMARY KEY, family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 target_type TEXT NOT NULL CHECK(target_type IN ('person','place','event')),
 target_id TEXT NOT NULL, storage_path TEXT NOT NULL UNIQUE,
 mime_type TEXT NOT NULL CHECK(mime_type IN ('image/jpeg','image/png')),
 byte_size INTEGER NOT NULL CHECK(byte_size BETWEEN 1 AND 5242880),
 width INTEGER NOT NULL CHECK(width BETWEEN 1 AND 4096), height INTEGER NOT NULL CHECK(height BETWEEN 1 AND 4096),
 sha256 TEXT NOT NULL, caption TEXT NOT NULL DEFAULT '', version INTEGER NOT NULL DEFAULT 1,
 created_at INTEGER NOT NULL, deleted_at INTEGER,
 FOREIGN KEY(family_id,target_type,target_id) REFERENCES records(family_id,kind,id)
) STRICT;
CREATE INDEX attachments_family ON attachments(family_id,target_type,target_id) WHERE deleted_at IS NULL;
CREATE TABLE activity (
 id INTEGER PRIMARY KEY, family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 actor_id TEXT REFERENCES users(id) ON DELETE SET NULL, action TEXT NOT NULL,
 entity_type TEXT NOT NULL, changed_fields TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(changed_fields)),
 occurred_at INTEGER NOT NULL
) STRICT;
CREATE INDEX activity_recent ON activity(family_id,occurred_at DESC);
CREATE TABLE deletion_jobs (
 id TEXT PRIMARY KEY, scope TEXT NOT NULL CHECK(scope IN ('account','family')),
 user_id TEXT REFERENCES users(id) ON DELETE CASCADE, family_id TEXT REFERENCES families(id) ON DELETE CASCADE,
 execute_after INTEGER NOT NULL
) STRICT;
CREATE TABLE rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, reset_at INTEGER NOT NULL) STRICT;
CREATE TABLE maintenance (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;
