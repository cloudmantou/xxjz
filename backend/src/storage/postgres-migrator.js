const fs = require('fs');
const path = require('path');

async function ensureMigrationsTable(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

function listMigrationFiles(migrationsDir) {
  if (!fs.existsSync(migrationsDir)) {
    return [];
  }

  return fs
    .readdirSync(migrationsDir)
    .filter((fileName) => fileName.endsWith('.sql'))
    .sort()
    .map((fileName) => ({
      version: fileName,
      filePath: path.join(migrationsDir, fileName)
    }));
}

async function getAppliedMigrationVersions(pool) {
  const result = await pool.query('SELECT version FROM schema_migrations ORDER BY version ASC');
  return new Set(result.rows.map((row) => row.version));
}

async function runPostgresMigrations({ pool, migrationsDir }) {
  await ensureMigrationsTable(pool);

  const files = listMigrationFiles(migrationsDir);
  const appliedVersions = await getAppliedMigrationVersions(pool);
  const applied = [];
  const skipped = [];

  for (const file of files) {
    if (appliedVersions.has(file.version)) {
      skipped.push(file.version);
      continue;
    }

    const sql = await fs.promises.readFile(file.filePath, 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file.version]);
      await client.query('COMMIT');
      applied.push(file.version);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  return {
    migrationsDir,
    pendingCount: 0,
    applied,
    skipped,
    files: files.map((file) => file.version)
  };
}

async function getMigrationStatus({ pool, migrationsDir }) {
  await ensureMigrationsTable(pool);
  const files = listMigrationFiles(migrationsDir);
  const appliedVersions = await getAppliedMigrationVersions(pool);

  return files.map((file) => ({
    version: file.version,
    applied: appliedVersions.has(file.version)
  }));
}

module.exports = {
  getMigrationStatus,
  runPostgresMigrations
};
