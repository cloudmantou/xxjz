const fs = require('fs');
const path = require('path');

const { Pool } = require('pg');
const { runPostgresMigrations } = require('./postgres-migrator');

function mapReleaseRow(row) {
  if (!row) {
    return null;
  }

  return {
    id: Number(row.id),
    releaseRef: row.release_ref,
    artifactType: row.artifact_type,
    snapshotRef: row.snapshot_ref,
    patchRef: row.patch_ref,
    parentReleaseId: row.parent_release_id ? Number(row.parent_release_id) : null,
    baseRulesVersion: row.base_rules_version,
    patchRulesVersion: row.patch_rules_version,
    configVersion: row.config_version,
    publishTime: new Date(row.publish_time).toISOString(),
    checksum: row.checksum,
    etag: row.etag,
    status: row.status,
    targetSelector: row.target_selector || {},
    rolloutStrategy: row.rollout_strategy || {},
    artifactJson: row.artifact_json || {},
    fullRulesJson: row.full_rules_json || [],
    tombstones: row.tombstones || [],
    noiseKeywords: row.noise_keywords || { add: [], remove: [] },
    note: row.note,
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString()
  };
}

function mapSnapshotRow(row) {
  if (!row) {
    return null;
  }

  return {
    id: Number(row.id),
    snapshotRef: row.snapshot_ref,
    baseRulesVersion: row.base_rules_version,
    patchRulesVersion: row.patch_rules_version,
    configVersion: row.config_version,
    checksum: row.checksum,
    etag: row.etag,
    artifactJson: row.artifact_json || [],
    validationResult: row.validation_result || {},
    parentReleaseId: row.parent_release_id ? Number(row.parent_release_id) : null,
    createdAt: new Date(row.created_at).toISOString()
  };
}

function mapPatchRow(row) {
  if (!row) {
    return null;
  }

  return {
    id: Number(row.id),
    patchRef: row.patch_ref,
    baseSnapshotRef: row.base_snapshot_ref,
    baseReleaseId: row.base_release_id ? Number(row.base_release_id) : null,
    patchRulesVersion: row.patch_rules_version,
    configVersion: row.config_version,
    checksum: row.checksum,
    artifactJson: row.artifact_json || {},
    validationResult: row.validation_result || {},
    createdAt: new Date(row.created_at).toISOString()
  };
}

function mapEmergencyRow(row) {
  if (!row) {
    return null;
  }

  return {
    id: Number(row.id),
    fingerprint: row.fingerprint,
    identity: row.identity,
    expiresAt: row.expires_at ? new Date(row.expires_at).toISOString() : null,
    reason: row.reason,
    status: row.status,
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString()
  };
}

function resolveExistingPath(candidates, fallback) {
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return fallback;
}

class PostgresRuleStore {
  constructor(options = {}) {
    this.connectionString = options.connectionString || process.env.DATABASE_URL;
    this.sqlPath =
      options.sqlPath ||
      resolveExistingPath(
        [
          path.join(process.cwd(), 'sql', 'init.sql'),
          path.join(process.cwd(), 'backend', 'sql', 'init.sql')
        ],
        path.join(__dirname, '..', '..', 'sql', 'init.sql')
      );
    this.migrationsDir =
      options.migrationsDir ||
      resolveExistingPath(
        [
          path.join(process.cwd(), 'sql', 'migrations'),
          path.join(process.cwd(), 'backend', 'sql', 'migrations')
        ],
        path.join(__dirname, '..', '..', 'sql', 'migrations')
      );
    this.pool = new Pool({
      connectionString: this.connectionString
    });
  }

  async initialize() {
    if (fs.existsSync(this.migrationsDir)) {
      await runPostgresMigrations({
        pool: this.pool,
        migrationsDir: this.migrationsDir
      });
      return;
    }

    const sql = await fs.promises.readFile(this.sqlPath, 'utf8');
    await this.pool.query(sql);
  }

  async listSnapshots() {
    const result = await this.pool.query(
      'SELECT * FROM rule_snapshots ORDER BY base_rules_version ASC, patch_rules_version ASC, id ASC'
    );
    return result.rows.map(mapSnapshotRow);
  }

  async getSnapshotByRef(snapshotRef) {
    const result = await this.pool.query(
      'SELECT * FROM rule_snapshots WHERE snapshot_ref = $1 LIMIT 1',
      [snapshotRef]
    );
    return mapSnapshotRow(result.rows[0]);
  }

  async insertSnapshot(snapshot) {
    const result = await this.pool.query(
      `INSERT INTO rule_snapshots (
        snapshot_ref, base_rules_version, patch_rules_version, config_version,
        checksum, etag, artifact_json, validation_result, parent_release_id
      ) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9)
      RETURNING *`,
      [
        snapshot.snapshotRef,
        snapshot.baseRulesVersion,
        snapshot.patchRulesVersion,
        snapshot.configVersion,
        snapshot.checksum,
        snapshot.etag,
        JSON.stringify(snapshot.artifactJson),
        JSON.stringify(snapshot.validationResult || {}),
        snapshot.parentReleaseId || null
      ]
    );
    return mapSnapshotRow(result.rows[0]);
  }

  async listPatches() {
    const result = await this.pool.query(
      'SELECT * FROM rule_patches ORDER BY patch_rules_version ASC, id ASC'
    );
    return result.rows.map(mapPatchRow);
  }

  async getPatchByRef(patchRef) {
    const result = await this.pool.query(
      'SELECT * FROM rule_patches WHERE patch_ref = $1 LIMIT 1',
      [patchRef]
    );
    return mapPatchRow(result.rows[0]);
  }

  async insertPatch(patch) {
    const result = await this.pool.query(
      `INSERT INTO rule_patches (
        patch_ref, base_snapshot_ref, base_release_id, patch_rules_version,
        config_version, checksum, artifact_json, validation_result
      ) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)
      RETURNING *`,
      [
        patch.patchRef,
        patch.baseSnapshotRef,
        patch.baseReleaseId || null,
        patch.patchRulesVersion,
        patch.configVersion,
        patch.checksum,
        JSON.stringify(patch.artifactJson),
        JSON.stringify(patch.validationResult || {})
      ]
    );
    return mapPatchRow(result.rows[0]);
  }

  async listReleases() {
    const result = await this.pool.query(
      'SELECT * FROM rule_releases ORDER BY config_version ASC, id ASC'
    );
    return result.rows.map(mapReleaseRow);
  }

  async getReleaseById(id) {
    const result = await this.pool.query(
      'SELECT * FROM rule_releases WHERE id = $1 LIMIT 1',
      [id]
    );
    return mapReleaseRow(result.rows[0]);
  }

  async getReleaseByRef(releaseRef) {
    const result = await this.pool.query(
      'SELECT * FROM rule_releases WHERE release_ref = $1 LIMIT 1',
      [releaseRef]
    );
    return mapReleaseRow(result.rows[0]);
  }

  async insertRelease(release) {
    const result = await this.pool.query(
      `INSERT INTO rule_releases (
        release_ref, artifact_type, snapshot_ref, patch_ref, parent_release_id,
        base_rules_version, patch_rules_version, config_version, publish_time,
        checksum, etag, status, target_selector, rollout_strategy, artifact_json,
        full_rules_json, tombstones, noise_keywords, note
      ) VALUES (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,$14::jsonb,$15::jsonb,
        $16::jsonb,$17::jsonb,$18::jsonb,$19
      ) RETURNING *`,
      [
        release.releaseRef,
        release.artifactType,
        release.snapshotRef,
        release.patchRef || null,
        release.parentReleaseId || null,
        release.baseRulesVersion,
        release.patchRulesVersion,
        release.configVersion,
        release.publishTime,
        release.checksum,
        release.etag,
        release.status,
        JSON.stringify(release.targetSelector || {}),
        JSON.stringify(release.rolloutStrategy || {}),
        JSON.stringify(release.artifactJson || {}),
        JSON.stringify(release.fullRulesJson || []),
        JSON.stringify(release.tombstones || []),
        JSON.stringify(release.noiseKeywords || { add: [], remove: [] }),
        release.note || null
      ]
    );
    return mapReleaseRow(result.rows[0]);
  }

  async updateRelease(id, updates) {
    const existing = await this.getReleaseById(id);
    if (!existing) {
      return null;
    }

    const merged = {
      ...existing,
      ...updates,
      updatedAt: new Date().toISOString()
    };

    const result = await this.pool.query(
      `UPDATE rule_releases
      SET status = $2,
          target_selector = $3::jsonb,
          rollout_strategy = $4::jsonb,
          tombstones = $5::jsonb,
          noise_keywords = $6::jsonb,
          note = $7,
          updated_at = NOW()
      WHERE id = $1
      RETURNING *`,
      [
        id,
        merged.status,
        JSON.stringify(merged.targetSelector || {}),
        JSON.stringify(merged.rolloutStrategy || {}),
        JSON.stringify(merged.tombstones || []),
        JSON.stringify(merged.noiseKeywords || { add: [], remove: [] }),
        merged.note || null
      ]
    );
    return mapReleaseRow(result.rows[0]);
  }

  async listEmergencyBlocks() {
    const result = await this.pool.query(
      'SELECT * FROM rule_emergency_blocks ORDER BY created_at ASC, id ASC'
    );
    return result.rows.map(mapEmergencyRow);
  }

  async upsertEmergencyBlock(block) {
    const result = await this.pool.query(
      `INSERT INTO rule_emergency_blocks (
        fingerprint, identity, expires_at, reason, status, updated_at
      ) VALUES ($1,$2::jsonb,$3,$4,$5,NOW())
      ON CONFLICT (fingerprint)
      DO UPDATE SET
        identity = EXCLUDED.identity,
        expires_at = EXCLUDED.expires_at,
        reason = EXCLUDED.reason,
        status = EXCLUDED.status,
        updated_at = NOW()
      RETURNING *`,
      [
        block.fingerprint,
        JSON.stringify(block.identity),
        block.expiresAt || null,
        block.reason || null,
        block.status || 'active'
      ]
    );
    await this.setRuntimeState({
      rulesConfigVersion: (await this.getRuntimeState()).rulesConfigVersion + 1
    });
    return mapEmergencyRow(result.rows[0]);
  }

  async removeEmergencyBlock(fingerprint) {
    const result = await this.pool.query(
      'DELETE FROM rule_emergency_blocks WHERE fingerprint = $1',
      [fingerprint]
    );
    if (result.rowCount > 0) {
      await this.setRuntimeState({
        rulesConfigVersion: (await this.getRuntimeState()).rulesConfigVersion + 1
      });
      return true;
    }
    return false;
  }

  async getRuntimeState() {
    const result = await this.pool.query(
      'SELECT rules_config_version FROM rule_runtime_state WHERE id = TRUE LIMIT 1'
    );
    return {
      rulesConfigVersion: result.rows[0]?.rules_config_version || 0
    };
  }

  async setRuntimeState(nextState) {
    const result = await this.pool.query(
      `INSERT INTO rule_runtime_state (id, rules_config_version, updated_at)
       VALUES (TRUE, $1, NOW())
       ON CONFLICT (id)
       DO UPDATE SET rules_config_version = EXCLUDED.rules_config_version, updated_at = NOW()
       RETURNING rules_config_version`,
      [nextState.rulesConfigVersion || 0]
    );
    return {
      rulesConfigVersion: result.rows[0]?.rules_config_version || 0
    };
  }
}

module.exports = {
  PostgresRuleStore
};
