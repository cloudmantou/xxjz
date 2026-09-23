const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const { once } = require('node:events');

const { createApp } = require('../src/app');
const { ConfigService } = require('../src/services/config-service');
const { RuleReleaseService } = require('../src/services/rule-release-service');
const { UsageAnalyticsService } = require('../src/services/usage-analytics-service');
const { MemoryRuleStore } = require('../src/storage/memory-rule-store');

function createRule(ruleId, keyWord, overrides = {}) {
  return {
    ruleId,
    keyWord,
    type: overrides.type ?? 1,
    memberCateId: overrides.memberCateId ?? 100,
    billsBookId: 0,
    keyWordSource: overrides.keyWordSource ?? 0,
    fundAccountId: overrides.fundAccountId ?? 2,
    memberId: null,
    memberTagIds: null,
    createDate: null,
    updateDate: null,
    searchTexts: [
      {
        index: 0,
        ruleId,
        ruleKind: 0,
        billSource: 2,
        minMatchValue: 0.5,
        matchType: 2,
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

async function startServer(app) {
  const server = http.createServer(app);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  const baseURL = `http://127.0.0.1:${address.port}`;
  return {
    server,
    baseURL
  };
}

test('rules endpoint serves full payloads and honors ETag 304 flow', async () => {
  const configService = new ConfigService({
    filePath: path.join(os.tmpdir(), `wuyoushu-config-${Date.now()}-${Math.random()}.json`)
  });
  const ruleReleaseService = new RuleReleaseService({
    store: new MemoryRuleStore(),
    enableEncryption: false,
    logger: {
      log() {},
      error() {}
    }
  });
  const usageAnalyticsService = new UsageAnalyticsService({
    filePath: path.join(os.tmpdir(), `wuyoushu-analytics-${Date.now()}-${Math.random()}.json`)
  });

  const app = await createApp({
    configService,
    ruleReleaseService,
    usageAnalyticsService,
    logger: {
      log() {},
      error() {}
    }
  });

  const publish = await ruleReleaseService.createFullReleaseDraft({
    rules: [createRule(101, '晚餐')],
    publish: true
  });
  assert.equal(publish.ok, true);

  const { server, baseURL } = await startServer(app);

  try {
    const first = await fetch(`${baseURL}/api/KeyWordMatchingRule/List`, {
      headers: {
        'X-Rules-Version': '0',
        'X-Rules-Config-Version': '0',
        'X-App-Version': '1.0.0',
        'X-Build': '100',
        'X-Platform': 'ios',
        'X-Channel': 'release',
        'X-Install-Id': 'device-a',
        'X-Cohort-Key': 'device-a'
      }
    });

    assert.equal(first.status, 200);
    const firstBody = await first.json();
    const etag = first.headers.get('etag');
    assert.ok(etag);
    assert.equal(firstBody.patchRulesVersion, publish.release.patchRulesVersion);
    assert.ok(Array.isArray(firstBody.fullData));
    assert.equal(firstBody.fullData[0].ruleId, 101);

    const second = await fetch(`${baseURL}/api/KeyWordMatchingRule/List`, {
      headers: {
        'X-Rules-Version': String(firstBody.patchRulesVersion),
        'X-Rules-Config-Version': String(firstBody.configVersion),
        'X-App-Version': '1.0.0',
        'X-Build': '100',
        'X-Platform': 'ios',
        'X-Channel': 'release',
        'X-Install-Id': 'device-a',
        'X-Cohort-Key': 'device-a',
        'If-None-Match': etag
      }
    });

    assert.equal(second.status, 304);
  } finally {
    server.close();
    await once(server, 'close');
  }
});
