const { createRulesChecksum, toQuotedETag } = require('../utils/crypto');

const RULE_KIND = {
  auto: 0,
  common: 1,
  local: 2
};

const RULE_BILL_SOURCE = {
  unknown: 0,
  wechat: 1,
  alipay: 2,
  generic: 3
};

const KEYWORD_SOURCE_TOKENS = {
  0: 'alipay_appear',
  1: 'alipay_credit',
  2: 'alipay_income',
  3: 'alipay_transfer',
  4: 'wechat_appear',
  5: 'wechat_credit',
  6: 'wechat_income',
  7: 'wechat_transfer'
};

const DEFAULT_TOMBSTONE_TTL_SECONDS = 60 * 60 * 24 * 30;

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeSourceApp(raw, fallbackKeywordSource) {
  if (raw === RULE_BILL_SOURCE.wechat || raw === 'wechat' || raw === 'weixin' || raw === '1') {
    return 'wechat';
  }
  if (raw === RULE_BILL_SOURCE.alipay || raw === 'alipay' || raw === 'ali' || raw === '2') {
    return 'alipay';
  }
  if (raw === RULE_BILL_SOURCE.generic || raw === 'generic' || raw === 'unknown' || raw === '3') {
    return 'generic';
  }

  if (fallbackKeywordSource !== undefined && fallbackKeywordSource !== null) {
    return normalizeSourceApp(keywordSourceToBillSource(fallbackKeywordSource));
  }

  return '*';
}

function keywordSourceToBillSource(keywordSource) {
  return Number(keywordSource) <= 3 ? RULE_BILL_SOURCE.alipay : RULE_BILL_SOURCE.wechat;
}

function normalizeSceneType(raw, fallbackKeywordSource) {
  if (typeof raw === 'string' && raw.trim()) {
    return raw.trim().toLowerCase();
  }

  if (raw !== undefined && raw !== null && KEYWORD_SOURCE_TOKENS[Number(raw)]) {
    return KEYWORD_SOURCE_TOKENS[Number(raw)];
  }

  if (fallbackKeywordSource !== undefined && fallbackKeywordSource !== null) {
    return KEYWORD_SOURCE_TOKENS[Number(fallbackKeywordSource)] || '*';
  }

  return '*';
}

function normalizeNamespace(raw) {
  if (raw === RULE_KIND.local || raw === 'local' || raw === '2') {
    return 'local';
  }
  if (raw === RULE_KIND.common || raw === 'common' || raw === '1') {
    return 'common';
  }
  if (raw === RULE_KIND.auto || raw === 'auto' || raw === '0') {
    return 'auto';
  }

  if (typeof raw === 'string' && raw.trim()) {
    return raw.trim().toLowerCase();
  }

  return '*';
}

function buildRuleIdentity(rule) {
  const firstSearchText = Array.isArray(rule.searchTexts) && rule.searchTexts.length > 0 ? rule.searchTexts[0] : null;
  return {
    sourceApp: normalizeSourceApp(firstSearchText?.billSource, rule.keyWordSource),
    sceneType: normalizeSceneType(rule.keyWordSource, rule.keyWordSource),
    ruleNamespace: normalizeNamespace(firstSearchText?.ruleKind),
    ruleId: Number(rule.ruleId)
  };
}

function normalizeIdentity(input) {
  if (!input) {
    return null;
  }

  if (typeof input === 'string') {
    const parts = input.split('|');
    if (parts.length === 4 && Number.isFinite(Number(parts[3]))) {
      return {
        sourceApp: parts[0] || '*',
        sceneType: parts[1] || '*',
        ruleNamespace: parts[2] || '*',
        ruleId: Number(parts[3])
      };
    }
    return null;
  }

  if (!Number.isFinite(Number(input.ruleId))) {
    return null;
  }

  return {
    sourceApp: normalizeSourceApp(input.sourceApp ?? input.billSource, input.keyWordSource),
    sceneType: normalizeSceneType(input.sceneType ?? input.keyWordSource, input.keyWordSource),
    ruleNamespace: normalizeNamespace(input.ruleNamespace ?? input.ruleKind),
    ruleId: Number(input.ruleId)
  };
}

function identityFingerprint(identity) {
  return `${identity.sourceApp}|${identity.sceneType}|${identity.ruleNamespace}|${identity.ruleId}`;
}

function matchesIdentity(pattern, candidate) {
  if (!pattern || !candidate) {
    return false;
  }

  if (Number(pattern.ruleId) !== Number(candidate.ruleId)) {
    return false;
  }

  const sourceMatches =
    pattern.sourceApp === '*' ||
    candidate.sourceApp === '*' ||
    pattern.sourceApp === candidate.sourceApp;
  const sceneMatches =
    pattern.sceneType === '*' ||
    candidate.sceneType === '*' ||
    pattern.sceneType === candidate.sceneType;
  const namespaceMatches =
    pattern.ruleNamespace === '*' ||
    candidate.ruleNamespace === '*' ||
    pattern.ruleNamespace === candidate.ruleNamespace;

  return sourceMatches && sceneMatches && namespaceMatches;
}

function normalizeTombstone(tombstone, now = new Date()) {
  const identity = normalizeIdentity(tombstone.key || tombstone.identity || tombstone);
  if (!identity) {
    return null;
  }

  let expiresAt = null;
  if (tombstone.expiresAt) {
    expiresAt = new Date(tombstone.expiresAt).toISOString();
  } else if (tombstone.ttlSeconds) {
    expiresAt = new Date(now.getTime() + Number(tombstone.ttlSeconds) * 1000).toISOString();
  }

  return {
    identity,
    fingerprint: identityFingerprint(identity),
    expiresAt,
    reason: tombstone.reason || null
  };
}

function normalizeTombstones(tombstones, now = new Date()) {
  const merged = new Map();

  for (const tombstone of tombstones || []) {
    const normalized = normalizeTombstone(tombstone, now);
    if (!normalized) {
      continue;
    }

    if (normalized.expiresAt && new Date(normalized.expiresAt).getTime() <= now.getTime()) {
      continue;
    }

    const existing = merged.get(normalized.fingerprint);
    if (!existing) {
      merged.set(normalized.fingerprint, normalized);
      continue;
    }

    const existingExpiry = existing.expiresAt ? new Date(existing.expiresAt).getTime() : Number.POSITIVE_INFINITY;
    const nextExpiry = normalized.expiresAt ? new Date(normalized.expiresAt).getTime() : Number.POSITIVE_INFINITY;
    if (nextExpiry >= existingExpiry) {
      merged.set(normalized.fingerprint, normalized);
    }
  }

  return [...merged.values()].sort((left, right) => left.fingerprint.localeCompare(right.fingerprint));
}

function deduplicateRulesByIdentity(rules) {
  const map = new Map();
  for (const rule of rules || []) {
    map.set(identityFingerprint(buildRuleIdentity(rule)), deepClone(rule));
  }
  return [...map.values()].sort((left, right) => Number(left.ruleId) - Number(right.ruleId));
}

function applyPriorityAdjustments(rulesMap, adjustments) {
  if (!Array.isArray(adjustments) || adjustments.length === 0) {
    return rulesMap;
  }

  for (const adjustment of adjustments) {
    const pattern = normalizeIdentity(adjustment.key || adjustment);
    if (!pattern) {
      continue;
    }

    for (const [fingerprint, rule] of rulesMap.entries()) {
      if (!matchesIdentity(pattern, buildRuleIdentity(rule))) {
        continue;
      }

      const searchTexts =
        Array.isArray(rule.searchTexts) && rule.searchTexts.length > 0
          ? deepClone(rule.searchTexts)
          : [
              {
                ruleId: Number(rule.ruleId),
                ruleKind: RULE_KIND.auto,
                billSource: keywordSourceToBillSource(rule.keyWordSource),
                minMatchValue: 0,
                matchType: 2,
                isFuzzy: true,
                isFuzzyLastValue: false,
                isOptional: false,
                isMutableLine: false,
                columnCount: 1,
                alignment: 0,
                candidateType: 2,
                subCandidateType: 0
              }
            ];

      for (const item of searchTexts) {
        if (adjustment.minMatchValue !== undefined && adjustment.minMatchValue !== null) {
          item.minMatchValue = Math.max(0, Number(adjustment.minMatchValue));
        }
        if (adjustment.minMatchValueDelta !== undefined && adjustment.minMatchValueDelta !== null) {
          item.minMatchValue = Math.max(
            0,
            Number(item.minMatchValue || 0) + Number(adjustment.minMatchValueDelta)
          );
        }
      }

      rulesMap.set(fingerprint, {
        ...rule,
        searchTexts
      });
    }
  }

  return rulesMap;
}

function mergePatchOntoRules(baseRules, patch, options = {}) {
  const now = options.now || new Date();
  const defaultTombstoneTTLSeconds =
    options.defaultTombstoneTTLSeconds || DEFAULT_TOMBSTONE_TTL_SECONDS;

  const rulesMap = new Map();
  for (const rule of baseRules || []) {
    rulesMap.set(identityFingerprint(buildRuleIdentity(rule)), deepClone(rule));
  }

  const deletePatterns = [];
  for (const ruleId of patch.deleteRuleIds || []) {
    deletePatterns.push(
      normalizeIdentity({
        sourceApp: '*',
        sceneType: '*',
        ruleNamespace: '*',
        ruleId
      })
    );
  }

  for (const key of patch.deleteRuleKeys || []) {
    const identity = normalizeIdentity(key);
    if (identity) {
      deletePatterns.push(identity);
    }
  }

  for (const pattern of deletePatterns) {
    for (const [fingerprint, rule] of [...rulesMap.entries()]) {
      if (matchesIdentity(pattern, buildRuleIdentity(rule))) {
        rulesMap.delete(fingerprint);
      }
    }
  }

  for (const rule of patch.upsert || []) {
    rulesMap.set(identityFingerprint(buildRuleIdentity(rule)), deepClone(rule));
  }

  applyPriorityAdjustments(rulesMap, patch.priorityAdjustments || []);

  const generatedDeleteTombstones = deletePatterns
    .filter(Boolean)
    .map((identity) => ({
      identity,
      reason: 'patch_delete',
      expiresAt: new Date(now.getTime() + defaultTombstoneTTLSeconds * 1000).toISOString()
    }));

  return {
    rules: [...rulesMap.values()].sort((left, right) => Number(left.ruleId) - Number(right.ruleId)),
    tombstones: normalizeTombstones(
      [...(patch.tombstones || []), ...generatedDeleteTombstones],
      now
    ),
    noiseKeywords: patch.noiseKeywords || { add: [], remove: [] }
  };
}

function applyRuleGuards(rules, tombstones, emergencyBlocks, now = new Date()) {
  const normalizedTombstones = normalizeTombstones(
    [
      ...(tombstones || []),
      ...(emergencyBlocks || []).map((block) => ({
        identity: block.identity,
        expiresAt: block.expiresAt,
        reason: block.reason || 'emergency_block'
      }))
    ],
    now
  );

  const filteredRules = (rules || []).filter((rule) => {
    const identity = buildRuleIdentity(rule);
    return !normalizedTombstones.some((tombstone) => matchesIdentity(tombstone.identity, identity));
  });

  return {
    rules: filteredRules,
    tombstones: normalizedTombstones
  };
}

function createDeliveryArtifacts({ rules, tombstones, noiseKeywords }) {
  const checksum = createRulesChecksum(rules);
  return {
    rules,
    tombstones: normalizeTombstones(tombstones || []),
    noiseKeywords: noiseKeywords || { add: [], remove: [] },
    checksum,
    etag: toQuotedETag(checksum)
  };
}

module.exports = {
  DEFAULT_TOMBSTONE_TTL_SECONDS,
  RULE_BILL_SOURCE,
  RULE_KIND,
  applyRuleGuards,
  buildRuleIdentity,
  createDeliveryArtifacts,
  deduplicateRulesByIdentity,
  identityFingerprint,
  matchesIdentity,
  mergePatchOntoRules,
  normalizeIdentity,
  normalizeTombstone,
  normalizeTombstones
};
