#!/usr/bin/env node

const path = require('path');

const { Pool } = require('pg');
const mysql = require('mysql2/promise');

const { loadEnvFiles } = require('./lib/load-env');
const { buildBootstrapReleaseInput } = require('../src/seed/bootstrap-release');
const { RuleReleaseService } = require('../src/services/rule-release-service');
const { createRuleStore } = require('../src/storage/create-store');
const { runMySQLMigrations } = require('../src/storage/mysql-migrator');
const { runPostgresMigrations } = require('../src/storage/postgres-migrator');

const backendRoot = path.join(__dirname, '..');
loadEnvFiles(backendRoot);

function printHelp() {
  console.log(`Usage: node scripts/db-reset.js --yes [--seed]

Options:
  --yes    Required safety switch
  --seed   Publish the bootstrap full release after migrations
  --help   Show this help text`);
}

async function main() {
  if (process.argv.includes('--help')) {
    printHelp();
    return;
  }

  if (!process.argv.includes('--yes')) {
    throw new Error('Refusing to reset database without --yes');
  }

  const driver =
    process.env.RULES_STORAGE || (process.env.MYSQL_URL || process.env.MYSQL_HOST ? 'mysql' : 'postgres');
  const pool =
    driver === 'mysql'
      ? process.env.MYSQL_URL
        ? mysql.createPool(process.env.MYSQL_URL)
        : mysql.createPool({
            host: process.env.MYSQL_HOST,
            port: Number(process.env.MYSQL_PORT || 3306),
            user: process.env.MYSQL_USER,
            password: process.env.MYSQL_PASSWORD,
            database: process.env.MYSQL_DATABASE,
            charset: 'utf8mb4',
            waitForConnections: true,
            connectionLimit: 5,
            timezone: 'Z'
          })
      : new Pool({
          connectionString: process.env.DATABASE_URL
        });
  const migrationsDir =
    driver === 'mysql'
      ? path.join(backendRoot, 'sql', 'mysql', 'migrations')
      : path.join(backendRoot, 'sql', 'migrations');

  try {
    const resetStatements =
      driver === 'mysql'
        ? [
            'DROP TABLE IF EXISTS rule_emergency_blocks',
            'DROP TABLE IF EXISTS rule_releases',
            'DROP TABLE IF EXISTS rule_patches',
            'DROP TABLE IF EXISTS rule_snapshots',
            'DROP TABLE IF EXISTS rule_runtime_state',
            'DROP TABLE IF EXISTS schema_migrations'
          ]
        : [
            'DROP TABLE IF EXISTS rule_emergency_blocks',
            'DROP TABLE IF EXISTS rule_releases',
            'DROP TABLE IF EXISTS rule_patches',
            'DROP TABLE IF EXISTS rule_snapshots',
            'DROP TABLE IF EXISTS rule_runtime_state',
            'DROP TABLE IF EXISTS schema_migrations',
            'DROP FUNCTION IF EXISTS touch_updated_at()'
          ];

    for (const statement of resetStatements) {
      await pool.query(statement);
    }

    if (driver === 'mysql') {
      await runMySQLMigrations({ pool, migrationsDir });
    } else {
      await runPostgresMigrations({ pool, migrationsDir });
    }
  } finally {
    await pool.end();
  }

  if (process.argv.includes('--seed')) {
    const store = createRuleStore({
      driver,
      migrationsDir
    });
    const service = new RuleReleaseService({
      store,
      enableEncryption: false
    });

    try {
      await service.initialize();
      const result = await service.createFullReleaseDraft(
        buildBootstrapReleaseInput('bootstrap seed release after db reset')
      );
      if (!result.ok) {
        throw new Error(`${result.error}: ${(result.details || []).join('; ')}`);
      }
      console.log(`Reset complete and seeded ${result.release.releaseRef}`);
    } finally {
      if (store.pool) {
        await store.pool.end();
      }
    }
    return;
  }

  console.log('Reset complete.');
}

main().catch((error) => {
  console.error('[db:reset] failed:', error.message);
  process.exitCode = 1;
});
