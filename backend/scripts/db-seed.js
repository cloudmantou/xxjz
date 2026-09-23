#!/usr/bin/env node

const path = require('path');

const { loadEnvFiles } = require('./lib/load-env');
const { buildBootstrapReleaseInput } = require('../src/seed/bootstrap-release');
const { RuleReleaseService } = require('../src/services/rule-release-service');
const { createRuleStore } = require('../src/storage/create-store');

const backendRoot = path.join(__dirname, '..');
loadEnvFiles(backendRoot);

function printHelp() {
  console.log(`Usage: node scripts/db-seed.js [--force]

Options:
  --force   Publish a new bootstrap full release even if releases already exist
  --help    Show this help text`);
}

async function main() {
  if (process.argv.includes('--help')) {
    printHelp();
    return;
  }

  const force = process.argv.includes('--force');
  const driver =
    process.env.RULES_STORAGE || (process.env.MYSQL_URL || process.env.MYSQL_HOST ? 'mysql' : 'postgres');
  const store = createRuleStore({
    driver,
    migrationsDir:
      driver === 'mysql'
        ? path.join(backendRoot, 'sql', 'mysql', 'migrations')
        : path.join(backendRoot, 'sql', 'migrations')
  });
  const service = new RuleReleaseService({
    store,
    enableEncryption: false
  });

  try {
    await service.initialize();
    const existingReleases = await service.listReleases();
    if (existingReleases.length > 0 && !force) {
      console.log(`Skipped seeding: ${existingReleases.length} release(s) already exist. Use --force to publish a new bootstrap release.`);
      return;
    }

    const result = await service.createFullReleaseDraft(
      buildBootstrapReleaseInput(force ? 'bootstrap seed release (forced)' : 'bootstrap seed release')
    );
    if (!result.ok) {
      throw new Error(`${result.error}: ${(result.details || []).join('; ')}`);
    }

    console.log(
      `Seeded release ${result.release.releaseRef} base=${result.release.baseRulesVersion} patch=${result.release.patchRulesVersion} config=${result.release.configVersion}`
    );
  } finally {
    if (store.pool) {
      await store.pool.end();
    }
  }
}

main().catch((error) => {
  console.error('[db:seed] failed:', error.message);
  process.exitCode = 1;
});
