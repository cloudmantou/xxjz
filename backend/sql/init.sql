CREATE TABLE IF NOT EXISTS rule_snapshots (
  id BIGSERIAL PRIMARY KEY,
  snapshot_ref TEXT NOT NULL UNIQUE,
  base_rules_version INTEGER NOT NULL,
  patch_rules_version INTEGER NOT NULL,
  config_version INTEGER NOT NULL,
  checksum TEXT NOT NULL,
  etag TEXT NOT NULL,
  artifact_json JSONB NOT NULL,
  validation_result JSONB NOT NULL,
  parent_release_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rule_patches (
  id BIGSERIAL PRIMARY KEY,
  patch_ref TEXT NOT NULL UNIQUE,
  base_snapshot_ref TEXT,
  base_release_id BIGINT,
  patch_rules_version INTEGER NOT NULL,
  config_version INTEGER NOT NULL,
  checksum TEXT NOT NULL,
  artifact_json JSONB NOT NULL,
  validation_result JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rule_releases (
  id BIGSERIAL PRIMARY KEY,
  release_ref TEXT NOT NULL UNIQUE,
  artifact_type TEXT NOT NULL,
  snapshot_ref TEXT NOT NULL,
  patch_ref TEXT,
  parent_release_id BIGINT,
  base_rules_version INTEGER NOT NULL,
  patch_rules_version INTEGER NOT NULL,
  config_version INTEGER NOT NULL,
  publish_time TIMESTAMPTZ NOT NULL,
  checksum TEXT NOT NULL,
  etag TEXT NOT NULL,
  status TEXT NOT NULL,
  target_selector JSONB NOT NULL DEFAULT '{}'::JSONB,
  rollout_strategy JSONB NOT NULL DEFAULT '{}'::JSONB,
  artifact_json JSONB NOT NULL,
  full_rules_json JSONB NOT NULL,
  tombstones JSONB NOT NULL DEFAULT '[]'::JSONB,
  noise_keywords JSONB NOT NULL DEFAULT '{"add":[],"remove":[]}'::JSONB,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rule_emergency_blocks (
  id BIGSERIAL PRIMARY KEY,
  fingerprint TEXT NOT NULL UNIQUE,
  identity JSONB NOT NULL,
  expires_at TIMESTAMPTZ,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rule_runtime_state (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE,
  rules_config_version INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (id = TRUE)
);

INSERT INTO rule_runtime_state (id, rules_config_version)
VALUES (TRUE, 0)
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_rule_snapshots_versions
  ON rule_snapshots (base_rules_version DESC, patch_rules_version DESC, config_version DESC);

CREATE INDEX IF NOT EXISTS idx_rule_patches_base_release
  ON rule_patches (base_release_id, patch_rules_version DESC);

CREATE INDEX IF NOT EXISTS idx_rule_releases_status_config
  ON rule_releases (status, config_version DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_rule_releases_snapshot_ref
  ON rule_releases (snapshot_ref);

CREATE INDEX IF NOT EXISTS idx_rule_emergency_blocks_status_expires
  ON rule_emergency_blocks (status, expires_at);

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rule_releases_touch_updated_at ON rule_releases;
CREATE TRIGGER trg_rule_releases_touch_updated_at
BEFORE UPDATE ON rule_releases
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_rule_emergency_blocks_touch_updated_at ON rule_emergency_blocks;
CREATE TRIGGER trg_rule_emergency_blocks_touch_updated_at
BEFORE UPDATE ON rule_emergency_blocks
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();
