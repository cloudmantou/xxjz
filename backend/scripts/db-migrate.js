#!/usr/bin/env node

const path = require('path');

const { Pool } = require('pg');
const mysql = require('mysql2/promise');

const { loadEnvFiles } = require('./lib/load-env');
const { getMigrationStatus: getMySQLMigrationStatus, runMySQLMigrations } = require('../src/storage/mysql-migrator');
const { getMigrationStatus, runPostgresMigrations } = require('../src/storage/postgres-migrator');

const backendRoot = path.join(__dirname, '..');
loadEnvFiles(backendRoot);

function printHelp() {
  console.log(`Usage: node scripts/db-migrate.js [--status]

Options:
  --status   Show migration status without applying pending files
  --help     Show this help text

Environment:
  PostgreSQL: DATABASE_URL
  MySQL: MYSQL_URL or MYSQL_HOST/MYSQL_PORT/MYSQL_USER/MYSQL_PASSWORD/MYSQL_DATABASE`);
}

function resolveDriver() {
  return process.env.RULES_STORAGE || (process.env.MYSQL_URL || process.env.MYSQL_HOST ? 'mysql' : 'postgres');
}

function createPostgresPool() {
  return new Pool({ connectionString: process.env.DATABASE_URL });
}

function createMySQLPool() {
  if (process.env.MYSQL_URL) {
    return mysql.createPool(process.env.MYSQL_URL);
  }

  return mysql.createPool({
    host: process.env.MYSQL_HOST,
    port: Number(process.env.MYSQL_PORT || 3306),
    user: process.env.MYSQL_USER,
    password: process.env.MYSQL_PASSWORD,
    database: process.env.MYSQL_DATABASE,
    charset: 'utf8mb4',
    waitForConnections: true,
    connectionLimit: 5,
    timezone: 'Z'
  });
}

async function main() {
  if (process.argv.includes('--help')) {
    printHelp();
    return;
  }

  const driver = resolveDriver();
  const migrationsDir =
    driver === 'mysql'
      ? path.join(backendRoot, 'sql', 'mysql', 'migrations')
      : path.join(backendRoot, 'sql', 'migrations');
  const pool = driver === 'mysql' ? createMySQLPool() : createPostgresPool();

  try {
    if (process.argv.includes('--status')) {
      const status =
        driver === 'mysql'
          ? await getMySQLMigrationStatus({ pool, migrationsDir })
          : await getMigrationStatus({ pool, migrationsDir });
      for (const item of status) {
        console.log(`${item.applied ? 'APPLIED' : 'PENDING'} ${item.version}`);
      }
      return;
    }

    const result =
      driver === 'mysql'
        ? await runMySQLMigrations({ pool, migrationsDir })
        : await runPostgresMigrations({ pool, migrationsDir });
    if (result.applied.length === 0) {
      console.log('No pending migrations.');
      return;
    }

    for (const version of result.applied) {
      console.log(`Applied ${version}`);
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[db:migrate] failed:', error.message);
  process.exitCode = 1;
});
