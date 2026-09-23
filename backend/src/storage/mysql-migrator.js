const fs = require('fs');
const path = require('path');

async function ensureMigrationsTable(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(255) PRIMARY KEY,
      applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
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
  const [rows] = await pool.query('SELECT version FROM schema_migrations ORDER BY version ASC');
  return new Set(rows.map((row) => row.version));
}

function splitSqlStatements(sql) {
  return sql
    .split(/;\s*(?:\r?\n|$)/)
    .map((statement) => statement.trim())
    .filter(Boolean);
}

async function runMySQLMigrations({ pool, migrationsDir }) {
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
    const statements = splitSqlStatements(sql);
    const connection = await pool.getConnection();

    try {
      await connection.beginTransaction();
      for (const statement of statements) {
        await connection.query(statement);
      }
      await connection.query('INSERT INTO schema_migrations (version) VALUES (?)', [file.version]);
      await connection.commit();
      applied.push(file.version);
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
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
  runMySQLMigrations
};
