const test = require('node:test');
const assert = require('node:assert/strict');

const { buildBootstrapReleaseInput, buildBootstrapRules } = require('../src/seed/bootstrap-release');
const { RuleReleaseService } = require('../src/services/rule-release-service');
const { RuleValidator } = require('../src/services/rule-validator');
const { MemoryRuleStore } = require('../src/storage/memory-rule-store');

test('bootstrap rules validate as a publishable full release', async () => {
  const validator = new RuleValidator();
  const rules = buildBootstrapRules();
  const validation = validator.validateRules(rules);

  assert.equal(validation.valid, true, validation.errors.join('; '));

  const service = new RuleReleaseService({
    store: new MemoryRuleStore(),
    enableEncryption: false
  });
  await service.initialize();

  const result = await service.createFullReleaseDraft(buildBootstrapReleaseInput());
  assert.equal(result.ok, true);
  assert.equal(result.release.fullRulesJson.length, rules.length);
});
