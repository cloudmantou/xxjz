const test = require('node:test');
const assert = require('node:assert/strict');

const { RuleReleaseService } = require('../src/services/rule-release-service');
const { MemoryRuleStore } = require('../src/storage/memory-rule-store');

function createRule(ruleId, keyWord, overrides = {}) {
  const keyWordSource = overrides.keyWordSource ?? 0;
  const billSource = overrides.billSource ?? (keyWordSource <= 3 ? 2 : 1);

  return {
    ruleId,
    keyWord,
    type: overrides.type ?? 1,
    memberCateId: overrides.memberCateId ?? 100,
    billsBookId: overrides.billsBookId ?? 0,
    keyWordSource,
    fundAccountId: overrides.fundAccountId ?? billSource,
    memberId: null,
    memberTagIds: null,
    createDate: null,
    updateDate: null,
    searchTexts: [
      {
        index: 0,
        ruleId,
        ruleKind: overrides.ruleKind ?? 0,
        billSource,
        minMatchValue: overrides.minMatchValue ?? 0.55,
        matchType: overrides.matchType ?? 2,
        isFuzzy: false,
        isFuzzyLastValue: false,
        isOptional: false,
        isMutableLine: false,
        columnCount: 1,
        alignment: 0,
        candidateType: 2,
        subCandidateType: 0
      }
    ]
  };
}

async function createService() {
  const service = new RuleReleaseService({
    store: new MemoryRuleStore(),
    enableEncryption: false,
    logger: {
      log() {},
      error() {}
    }
  });
  await service.initialize();
  return service;
}

function standardMeta(overrides = {}) {
  return {
    rulesVersion: 0,
    rulesConfigVersion: 0,
    appVersion: '1.0.0',
    build: '100',
    platform: 'ios',
    channel: 'release',
    cohortKey: 'test-device',
    installId: 'test-device',
    format: 'standard',
    ...overrides
  };
}

test('rejects full releases with duplicate ruleId values', async () => {
  const service = await createService();
  const result = await service.createFullReleaseDraft({
    rules: [
      createRule(101, '瑞幸咖啡', { keyWordSource: 0 }),
      createRule(101, 'luckin', { keyWordSource: 4 })
    ]
  });

  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_rules');
  assert.match(result.details.join(' '), /duplicate ruleId 101/);
});

test('patch releases apply upsert delete priority adjustment and tombstones', async () => {
  const service = await createService();
  const full = await service.createFullReleaseDraft({
    rules: [createRule(101, '瑞幸咖啡'), createRule(202, '工资', { type: 2, keyWordSource: 6 })]
  });
  assert.equal(full.ok, true);

  const patch = await service.createPatchReleaseDraft({
    patch: {
      upsert: [createRule(101, '库迪咖啡', { minMatchValue: 0.61 })],
      deleteRuleIds: [202],
      priorityAdjustments: [
        {
          ruleId: 101,
          minMatchValue: 0.88
        }
      ],
      noiseKeywords: {
        add: ['尾号1234'],
        remove: []
      }
    }
  });

  assert.equal(patch.ok, true);
  assert.equal(patch.release.artifactType, 'patch');
  assert.equal(patch.release.fullRulesJson.length, 1);
  assert.equal(patch.release.fullRulesJson[0].keyWord, '库迪咖啡');
  assert.equal(patch.release.fullRulesJson[0].searchTexts[0].minMatchValue, 0.88);
  assert.equal(patch.release.tombstones.length, 1);
  assert.equal(patch.release.tombstones[0].identity.ruleId, 202);
  assert.deepEqual(patch.release.noiseKeywords, {
    add: ['尾号1234'],
    remove: []
  });
});

test('config-only rule state bumps do not incorrectly return 304', async () => {
  const service = await createService();
  const full = await service.createFullReleaseDraft({
    rules: [createRule(101, '午餐')]
  });
  assert.equal(full.ok, true);

  await service.store.setRuntimeState({
    rulesConfigVersion: full.release.configVersion + 1
  });

  const response = await service.buildReadResponse(
    standardMeta({
      rulesVersion: full.release.patchRulesVersion,
      rulesConfigVersion: full.release.configVersion,
      ifNoneMatch: full.release.etag
    })
  );

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.patchRulesVersion, full.release.patchRulesVersion);
  assert.equal(response.body.configVersion, full.release.configVersion + 1);
  assert.deepEqual(response.body.patchData, {});
});

test('rollback republishes the target snapshot as a new full release', async () => {
  const service = await createService();
  const first = await service.createFullReleaseDraft({
    rules: [createRule(101, '早餐')]
  });
  const second = await service.createFullReleaseDraft({
    rules: [createRule(101, '下午茶')]
  });

  assert.equal(first.ok, true);
  assert.equal(second.ok, true);

  const rollback = await service.rollbackToRelease({
    releaseId: first.release.id,
    note: 'manual rollback'
  });

  assert.equal(rollback.ok, true);
  assert.equal(rollback.release.artifactType, 'full');
  assert.equal(rollback.release.note, 'manual rollback');
  assert.deepEqual(rollback.release.fullRulesJson, first.release.fullRulesJson);
  assert.ok(rollback.release.configVersion > second.release.configVersion);
});
