const fs = require('fs');
const path = require('path');

const mysql = require('mysql2/promise');

const { runMySQLMigrations } = require('./mysql-migrator');

function parseJSON(value, fallback) {
  if (value === null || value === undefined || value === '') {
    return fallback;
  }

  if (typeof value === 'object') {
    return value;
  }

  try {
    return JSON.parse(value);
  } catch (error) {
    return fallback;
  }
}

function toISOString(value) {
  if (!value) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  return new Date(value).toISOString();
}

function toMySQLDateTime(value) {
  if (!value) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString().slice(0, 19).replace('T', ' ');
}

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
    publishTime: toISOString(row.publish_time),
    checksum: row.checksum,
    etag: row.etag,
    status: row.status,
    targetSelector: parseJSON(row.target_selector, {}),
    rolloutStrategy: parseJSON(row.rollout_strategy, {}),
    artifactJson: parseJSON(row.artifact_json, {}),
    fullRulesJson: parseJSON(row.full_rules_json, []),
    tombstones: parseJSON(row.tombstones, []),
    noiseKeywords: parseJSON(row.noise_keywords, { add: [], remove: [] }),
    note: row.note,
    createdAt: toISOString(row.created_at),
    updatedAt: toISOString(row.updated_at)
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
    artifactJson: parseJSON(row.artifact_json, []),
    validationResult: parseJSON(row.validation_result, {}),
    parentReleaseId: row.parent_release_id ? Number(row.parent_release_id) : null,
    createdAt: toISOString(row.created_at)
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
    artifactJson: parseJSON(row.artifact_json, {}),
    validationResult: parseJSON(row.validation_result, {}),
    createdAt: toISOString(row.created_at)
  };
}

function mapEmergencyRow(row) {
  if (!row) {
    return null;
  }

  return {
    id: Number(row.id),
    fingerprint: row.fingerprint,
    identity: parseJSON(row.identity, {}),
    expiresAt: toISOString(row.expires_at),
    reason: row.reason,
    status: row.status,
    createdAt: toISOString(row.created_at),
    updatedAt: toISOString(row.updated_at)
  };
}

function buildMySQLConnectionOptions(options = {}) {
  if (options.connectionString) {
    const url = new URL(options.connectionString);
    return {
      host: url.hostname,
      port: url.port ? Number(url.port) : 3306,
      user: decodeURIComponent(url.username),
      password: decodeURIComponent(url.password),
      database: url.pathname.replace(/^\//, ''),
      charset: 'utf8mb4',
      waitForConnections: true,
      connectionLimit: 10,
      timezone: 'Z'
    };
  }

  return {
    host: options.host || process.env.MYSQL_HOST || '127.0.0.1',
    port: Number(options.port || process.env.MYSQL_PORT || 3306),
    user: options.user || process.env.MYSQL_USER,
    password: options.password || process.env.MYSQL_PASSWORD,
    database: options.database || process.env.MYSQL_DATABASE,
    charset: 'utf8mb4',
    waitForConnections: true,
    connectionLimit: 10,
    timezone: 'Z'
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

class MySQLRuleStore {
  constructor(options = {}) {
    this.connectionOptions = buildMySQLConnectionOptions({
      connectionString: options.connectionString || process.env.MYSQL_URL,
      host: options.host,
      port: options.port,
      user: options.user,
      password: options.password,
      database: options.database
    });
    this.sqlPath =
      options.sqlPath ||
      resolveExistingPath(
        [
          path.join(process.cwd(), 'sql', 'mysql', 'init.sql'),
          path.join(process.cwd(), 'backend', 'sql', 'mysql', 'init.sql')
        ],
        path.join(__dirname, '..', '..', 'sql', 'mysql', 'init.sql')
      );
    this.migrationsDir =
      options.migrationsDir ||
      resolveExistingPath(
        [
          path.join(process.cwd(), 'sql', 'mysql', 'migrations'),
          path.join(process.cwd(), 'backend', 'sql', 'mysql', 'migrations')
        ],
        path.join(__dirname, '..', '..', 'sql', 'mysql', 'migrations')
      );
    this.pool = mysql.createPool(this.connectionOptions);
  }

  async initialize() {
    if (fs.existsSync(this.migrationsDir)) {
      await runMySQLMigrations({
        pool: this.pool,
        migrationsDir: this.migrationsDir
      });
      return;
    }

    const sql = await fs.promises.readFile(this.sqlPath, 'utf8');
    const statements = sql
      .split(/;\s*(?:\r?\n|$)/)
      .map((statement) => statement.trim())
      .filter(Boolean);
    for (const statement of statements) {
      await this.pool.query(statement);
    }
  }

  async listSnapshots() {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_snapshots ORDER BY base_rules_version ASC, patch_rules_version ASC, id ASC'
    );
    return rows.map(mapSnapshotRow);
  }

  async getSnapshotByRef(snapshotRef) {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_snapshots WHERE snapshot_ref = ? LIMIT 1',
      [snapshotRef]
    );
    return mapSnapshotRow(rows[0]);
  }

  async insertSnapshot(snapshot) {
    await this.pool.query(
      `INSERT INTO rule_snapshots (
        snapshot_ref, base_rules_version, patch_rules_version, config_version,
        checksum, etag, artifact_json, validation_result, parent_release_id
      ) VALUES (?,?,?,?,?,?,?,?,?)`,
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
    return this.getSnapshotByRef(snapshot.snapshotRef);
  }

  async listPatches() {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_patches ORDER BY patch_rules_version ASC, id ASC'
    );
    return rows.map(mapPatchRow);
  }

  async getPatchByRef(patchRef) {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_patches WHERE patch_ref = ? LIMIT 1',
      [patchRef]
    );
    return mapPatchRow(rows[0]);
  }

  async insertPatch(patch) {
    await this.pool.query(
      `INSERT INTO rule_patches (
        patch_ref, base_snapshot_ref, base_release_id, patch_rules_version,
        config_version, checksum, artifact_json, validation_result
      ) VALUES (?,?,?,?,?,?,?,?)`,
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
    return this.getPatchByRef(patch.patchRef);
  }

  async listReleases() {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_releases ORDER BY config_version ASC, id ASC'
    );
    return rows.map(mapReleaseRow);
  }

  async getReleaseById(id) {
    const [rows] = await this.pool.query('SELECT * FROM rule_releases WHERE id = ? LIMIT 1', [id]);
    return mapReleaseRow(rows[0]);
  }

  async getReleaseByRef(releaseRef) {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_releases WHERE release_ref = ? LIMIT 1',
      [releaseRef]
    );
    return mapReleaseRow(rows[0]);
  }

  async insertRelease(release) {
    await this.pool.query(
      `INSERT INTO rule_releases (
        release_ref, artifact_type, snapshot_ref, patch_ref, parent_release_id,
        base_rules_version, patch_rules_version, config_version, publish_time,
        checksum, etag, status, target_selector, rollout_strategy, artifact_json,
        full_rules_json, tombstones, noise_keywords, note
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        release.releaseRef,
        release.artifactType,
        release.snapshotRef,
        release.patchRef || null,
        release.parentReleaseId || null,
        release.baseRulesVersion,
        release.patchRulesVersion,
        release.configVersion,
        toMySQLDateTime(release.publishTime),
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
    return this.getReleaseByRef(release.releaseRef);
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

    await this.pool.query(
      `UPDATE rule_releases
      SET status = ?,
          target_selector = ?,
          rollout_strategy = ?,
          tombstones = ?,
          noise_keywords = ?,
          note = ?
      WHERE id = ?`,
      [
        merged.status,
        JSON.stringify(merged.targetSelector || {}),
        JSON.stringify(merged.rolloutStrategy || {}),
        JSON.stringify(merged.tombstones || []),
        JSON.stringify(merged.noiseKeywords || { add: [], remove: [] }),
        merged.note || null,
        id
      ]
    );
    return this.getReleaseById(id);
  }

  async listEmergencyBlocks() {
    const [rows] = await this.pool.query(
      'SELECT * FROM rule_emergency_blocks ORDER BY created_at ASC, id ASC'
    );
    return rows.map(mapEmergencyRow);
  }

  async upsertEmergencyBlock(block) {
    await this.pool.query(
      `INSERT INTO rule_emergency_blocks (
        fingerprint, identity, expires_at, reason, status
      ) VALUES (?,?,?,?,?)
      ON DUPLICATE KEY UPDATE
        identity = VALUES(identity),
        expires_at = VALUES(expires_at),
        reason = VALUES(reason),
        status = VALUES(status)`,
      [
        block.fingerprint,
        JSON.stringify(block.identity),
        toMySQLDateTime(block.expiresAt),
        block.reason || null,
        block.status || 'active'
      ]
    );

    const runtimeState = await this.getRuntimeState();
    await this.setRuntimeState({
      rulesConfigVersion: runtimeState.rulesConfigVersion + 1
    });

    const [rows] = await this.pool.query(
      'SELECT * FROM rule_emergency_blocks WHERE fingerprint = ? LIMIT 1',
      [block.fingerprint]
    );
    return mapEmergencyRow(rows[0]);
  }

  async removeEmergencyBlock(fingerprint) {
    const [result] = await this.pool.query(
      'DELETE FROM rule_emergency_blocks WHERE fingerprint = ?',
      [fingerprint]
    );
    if (result.affectedRows > 0) {
      const runtimeState = await this.getRuntimeState();
      await this.setRuntimeState({
        rulesConfigVersion: runtimeState.rulesConfigVersion + 1
      });
      return true;
    }
    return false;
  }

  async getRuntimeState() {
    const [rows] = await this.pool.query(
      'SELECT rules_config_version FROM rule_runtime_state WHERE id = 1 LIMIT 1'
    );
    return {
      rulesConfigVersion: rows[0]?.rules_config_version || 0
    };
  }

  async setRuntimeState(nextState) {
    await this.pool.query(
      `INSERT INTO rule_runtime_state (id, rules_config_version)
       VALUES (1, ?)
       ON DUPLICATE KEY UPDATE
         rules_config_version = VALUES(rules_config_version),
         updated_at = CURRENT_TIMESTAMP`,
      [nextState.rulesConfigVersion || 0]
    );
    return this.getRuntimeState();
  }
}

module.exports = {
  MySQLRuleStore
};
