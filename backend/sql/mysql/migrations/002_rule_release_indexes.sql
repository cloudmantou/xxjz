CREATE INDEX idx_rule_snapshots_versions
  ON rule_snapshots (base_rules_version, patch_rules_version, config_version);

CREATE INDEX idx_rule_patches_base_release
  ON rule_patches (base_release_id, patch_rules_version);

CREATE INDEX idx_rule_releases_status_config
  ON rule_releases (status, config_version, id);

CREATE INDEX idx_rule_releases_snapshot_ref
  ON rule_releases (snapshot_ref(191));

CREATE INDEX idx_rule_emergency_blocks_status_expires
  ON rule_emergency_blocks (status, expires_at);
