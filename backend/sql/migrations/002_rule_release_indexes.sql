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
