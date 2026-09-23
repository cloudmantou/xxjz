const {
  aesEncryptCFB,
  normalizeETag,
  sha256Hex,
  toQuotedETag
} = require('../utils/crypto');
const { compareSemverLike, matchesRange } = require('../utils/version');
const {
  RULE_BILL_SOURCE,
  applyRuleGuards,
  buildRuleIdentity,
  createDeliveryArtifacts,
  deduplicateRulesByIdentity,
  identityFingerprint,
  mergePatchOntoRules,
  normalizeIdentity
} = require('./rule-merge');
const { RuleValidator } = require('./rule-validator');

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function randomRef(prefix) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function defaultRolloutStrategy(input = {}) {
  const normalizedType = ['immediate', 'linear'].includes(input.type) ? input.type : 'immediate';
  return {
    type: normalizedType,
    stepPercentage: Math.max(1, Math.min(100, Number(input.stepPercentage || input.percentage || 100))),
    durationMinutes: Math.max(1, Number(input.durationMinutes || 60)),
    bakeMinutes: Math.max(0, Number(input.bakeMinutes || 0))
  };
}

function defaultTargetSelector(input = {}) {
  return {
    platforms: Array.isArray(input.platforms) ? input.platforms : [],
    channels: Array.isArray(input.channels) ? input.channels : [],
    builds: Array.isArray(input.builds) ? input.builds : [],
    appVersion: input.appVersion || {}
  };
}

function parseVersionHeader(value) {
  const parsed = parseInt(value || '0', 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

class RuleReleaseService {
  constructor(options) {
    this.store = options.store;
    this.validator = options.validator || new RuleValidator();
    this.now = options.now || (() => new Date());
    this.logger = options.logger || console;
    this.encryption = {
      enabled: options.enableEncryption ?? process.env.ENABLE_ENCRYPTION === 'true',
      key: options.aesKey || process.env.AES_KEY || 'your-16byte-key!!',
      iv: options.aesIV || process.env.AES_IV || 'your-16byte-iv!!!'
    };
  }

  async initialize() {
    await this.store.initialize();
  }

  async listReleases() {
    return this.store.listReleases();
  }

  async getRelease(id) {
    return this.store.getReleaseById(id);
  }

  async listEmergencyBlocks() {
    return this.store.listEmergencyBlocks();
  }

  async createFullReleaseDraft(input) {
    const rules = deduplicateRulesByIdentity(input.rules || []);
    const validation = this.validator.validateRules(rules);
    if (!validation.valid) {
      return {
        ok: false,
        statusCode: 400,
        error: 'invalid_rules',
        details: validation.errors
      };
    }

    const latest = await this.getLatestRelease();
    const runtimeState = await this.store.getRuntimeState();
    const baseRulesVersion = latest ? latest.baseRulesVersion + 1 : 1;
    const patchRulesVersion = baseRulesVersion;
    const configVersion = Math.max(latest?.configVersion || 0, runtimeState.rulesConfigVersion || 0) + 1;
    const publishTime = this.now().toISOString();
    const snapshotArtifact = createDeliveryArtifacts({
      rules,
      tombstones: [],
      noiseKeywords: { add: [], remove: [] }
    });
    const snapshot = await this.store.insertSnapshot({
      snapshotRef: randomRef('snapshot-full'),
      baseRulesVersion,
      patchRulesVersion,
      configVersion,
      checksum: snapshotArtifact.checksum,
      etag: snapshotArtifact.etag,
      artifactJson: rules,
      validationResult: {
        valid: true,
        rules: rules.length
      },
      parentReleaseId: latest?.id || null
    });

    const release = await this.store.insertRelease({
      releaseRef: randomRef('release'),
      artifactType: 'full',
      snapshotRef: snapshot.snapshotRef,
      patchRef: null,
      parentReleaseId: latest?.id || null,
      baseRulesVersion,
      patchRulesVersion,
      configVersion,
      publishTime,
      checksum: snapshotArtifact.checksum,
      etag: snapshotArtifact.etag,
      status: input.publish === false ? 'draft' : this.statusForPublish(input.rolloutStrategy),
      targetSelector: defaultTargetSelector(input.targetSelector),
      rolloutStrategy: defaultRolloutStrategy(input.rolloutStrategy),
      artifactJson: rules,
      fullRulesJson: rules,
      tombstones: [],
      noiseKeywords: { add: [], remove: [] },
      note: input.note || null
    });

    if (release.status !== 'draft') {
      await this.reconcileActiveStatuses(release);
    }

    return {
      ok: true,
      statusCode: 201,
      release
    };
  }

  async createPatchReleaseDraft(input) {
    const patch = this.normalizePatchEnvelope(input.patch || input);
    const patchValidation = this.validator.validatePatchEnvelope(patch);
    if (!patchValidation.valid) {
      return {
        ok: false,
        statusCode: 400,
        error: 'invalid_patch',
        details: patchValidation.errors
      };
    }

    const baselineRelease =
      (input.baseReleaseId && (await this.store.getReleaseById(input.baseReleaseId))) ||
      (await this.getLatestRelease());
    if (!baselineRelease) {
      return {
        ok: false,
        statusCode: 409,
        error: 'missing_baseline_release',
        details: ['create a full release before publishing patches']
      };
    }

    const merged = mergePatchOntoRules(baselineRelease.fullRulesJson, patch, {
      now: this.now()
    });
    const validation = this.validator.validateRules(merged.rules);
    if (!validation.valid) {
      return {
        ok: false,
        statusCode: 400,
        error: 'invalid_merged_rules',
        details: validation.errors
      };
    }

    const runtimeState = await this.store.getRuntimeState();
    const configVersion = Math.max(baselineRelease.configVersion, runtimeState.rulesConfigVersion || 0) + 1;
    const patchRulesVersion = baselineRelease.patchRulesVersion + 1;
    const publishTime = this.now().toISOString();
    const delivery = createDeliveryArtifacts({
      rules: merged.rules,
      tombstones: merged.tombstones,
      noiseKeywords: merged.noiseKeywords
    });

    const snapshot = await this.store.insertSnapshot({
      snapshotRef: randomRef('snapshot-patch'),
      baseRulesVersion: baselineRelease.baseRulesVersion,
      patchRulesVersion,
      configVersion,
      checksum: delivery.checksum,
      etag: delivery.etag,
      artifactJson: merged.rules,
      validationResult: {
        valid: true,
        rules: merged.rules.length,
        patch: true
      },
      parentReleaseId: baselineRelease.id
    });

    const storedPatch = await this.store.insertPatch({
      patchRef: randomRef('patch'),
      baseSnapshotRef: baselineRelease.snapshotRef,
      baseReleaseId: baselineRelease.id,
      patchRulesVersion,
      configVersion,
      checksum: sha256Hex(JSON.stringify(patch)),
      artifactJson: patch,
      validationResult: {
        valid: true
      }
    });

    const release = await this.store.insertRelease({
      releaseRef: randomRef('release'),
      artifactType: 'patch',
      snapshotRef: snapshot.snapshotRef,
      patchRef: storedPatch.patchRef,
      parentReleaseId: baselineRelease.id,
      baseRulesVersion: baselineRelease.baseRulesVersion,
      patchRulesVersion,
      configVersion,
      publishTime,
      checksum: delivery.checksum,
      etag: delivery.etag,
      status: input.publish === false ? 'draft' : this.statusForPublish(input.rolloutStrategy),
      targetSelector: defaultTargetSelector(input.targetSelector || baselineRelease.targetSelector),
      rolloutStrategy: defaultRolloutStrategy(input.rolloutStrategy),
      artifactJson: patch,
      fullRulesJson: merged.rules,
      tombstones: merged.tombstones,
      noiseKeywords: merged.noiseKeywords,
      note: input.note || null
    });

    if (release.status !== 'draft') {
      await this.reconcileActiveStatuses(release);
    }

    return {
      ok: true,
      statusCode: 201,
      release
    };
  }

  async publishRelease(id, overrides = {}) {
    const release = await this.store.getReleaseById(id);
    if (!release) {
      return {
        ok: false,
        statusCode: 404,
        error: 'release_not_found'
      };
    }

    const updated = await this.store.updateRelease(id, {
      status: this.statusForPublish(overrides.rolloutStrategy || release.rolloutStrategy),
      rolloutStrategy: defaultRolloutStrategy(overrides.rolloutStrategy || release.rolloutStrategy),
      targetSelector: defaultTargetSelector(overrides.targetSelector || release.targetSelector),
      note: overrides.note || release.note
    });

    await this.reconcileActiveStatuses(updated);
    return {
      ok: true,
      statusCode: 200,
      release: updated
    };
  }

  async rollbackToRelease(input = {}) {
    const releases = await this.store.listReleases();
    const latest = this.pickLatestRelease(releases);
    const target =
      (input.releaseId && (await this.store.getReleaseById(input.releaseId))) ||
      (input.releaseRef && (await this.store.getReleaseByRef(input.releaseRef))) ||
      releases
        .filter((item) => item.status !== 'draft' && latest && item.id !== latest.id)
        .sort((left, right) => right.configVersion - left.configVersion)[0];

    if (!target) {
      return {
        ok: false,
        statusCode: 404,
        error: 'rollback_target_not_found'
      };
    }

    return this.createFullReleaseDraft({
      rules: target.fullRulesJson,
      publish: true,
      rolloutStrategy: {
        type: 'immediate',
        percentage: 100
      },
      targetSelector: target.targetSelector,
      note: input.note || `rollback:${target.releaseRef}`
    });
  }

  async addEmergencyBlock(input) {
    const identity = normalizeIdentity(input.identity || input);
    if (!identity) {
      return {
        ok: false,
        statusCode: 400,
        error: 'invalid_identity'
      };
    }

    const expiresAt = input.expiresAt
      ? new Date(input.expiresAt).toISOString()
      : input.ttlSeconds
        ? new Date(this.now().getTime() + Number(input.ttlSeconds) * 1000).toISOString()
        : null;

    const block = await this.store.upsertEmergencyBlock({
      fingerprint: identityFingerprint(identity),
      identity,
      expiresAt,
      reason: input.reason || null,
      status: 'active'
    });

    return {
      ok: true,
      statusCode: 201,
      block
    };
  }

  async removeEmergencyBlock(fingerprint) {
    const removed = await this.store.removeEmergencyBlock(fingerprint);
    return {
      ok: removed,
      statusCode: removed ? 200 : 404
    };
  }

  async buildReadResponse(requestMeta) {
    await this.finalizeExpiredRollouts();

    const releases = await this.store.listReleases();
    const stable = this.pickLatestRelease(releases.filter((item) => item.status === 'published'));
    const rolling = this.pickLatestRelease(releases.filter((item) => item.status === 'rolling_out'));
    const selected =
      (rolling && (await this.shouldServeRollingRelease(rolling, requestMeta))) ? rolling : stable;

    if (!selected) {
      return {
        statusCode: 404,
        headers: {},
        body: {
          code: 404,
          message: 'No published release',
          data: null
        }
      };
    }

    const runtimeState = await this.store.getRuntimeState();
    const emergencyBlocks = await this.activeEmergencyBlocks();
    const guarded = applyRuleGuards(
      selected.fullRulesJson,
      selected.tombstones,
      emergencyBlocks,
      this.now()
    );
    const effectiveConfigVersion = Math.max(
      selected.configVersion,
      runtimeState.rulesConfigVersion || 0
    );
    const delivery = createDeliveryArtifacts({
      rules: guarded.rules,
      tombstones: guarded.tombstones,
      noiseKeywords: selected.noiseKeywords
    });

    const clientPatchVersion = parseVersionHeader(requestMeta.rulesVersion);
    const clientConfigVersion = parseVersionHeader(requestMeta.rulesConfigVersion);
    const ifNoneMatch = normalizeETag(requestMeta.ifNoneMatch);
    const legacyFormat = requestMeta.format === 'legacy';
    if (
      ifNoneMatch &&
      ifNoneMatch === normalizeETag(delivery.etag) &&
      clientPatchVersion === selected.patchRulesVersion &&
      clientConfigVersion >= effectiveConfigVersion
    ) {
      return {
        statusCode: 304,
        headers: {
          ETag: delivery.etag
        },
        body: null
      };
    }

    if (legacyFormat) {
      return {
        statusCode: 200,
        headers: {
          ETag: delivery.etag
        },
        body: {
          code: 0,
          message: 'success',
          data: guarded.rules,
          version: selected.patchRulesVersion
        }
      };
    }

    if (
      clientPatchVersion === selected.patchRulesVersion &&
      clientConfigVersion >= effectiveConfigVersion
    ) {
      return {
        statusCode: 200,
        headers: {
          ETag: delivery.etag
        },
        body: {
          code: 0,
          message: 'Already up to date',
          baseRulesVersion: selected.baseRulesVersion,
          patchRulesVersion: selected.patchRulesVersion,
          configVersion: effectiveConfigVersion,
          publishTime: selected.publishTime,
          checksum: delivery.checksum,
          encrypted: false
        }
      };
    }

    const response = {
      code: 0,
      message: 'success',
      baseRulesVersion: selected.baseRulesVersion,
      patchRulesVersion: selected.patchRulesVersion,
      configVersion: effectiveConfigVersion,
      publishTime: selected.publishTime,
      checksum: delivery.checksum,
      encrypted: this.encryption.enabled,
      snapshotRef: selected.snapshotRef
    };

    if (guarded.tombstones.length > 0) {
      response.tombstones = guarded.tombstones.map((item) => ({
        ...item.identity,
        reason: item.reason,
        expiresAt: item.expiresAt
      }));
    }

    if (
      selected.noiseKeywords &&
      ((selected.noiseKeywords.add || []).length > 0 || (selected.noiseKeywords.remove || []).length > 0)
    ) {
      response.noiseKeywords = selected.noiseKeywords;
    }

    if (
      clientPatchVersion === selected.patchRulesVersion &&
      clientConfigVersion < effectiveConfigVersion
    ) {
      response.patchData = this.encodePayload({});
      return {
        statusCode: 200,
        headers: {
          ETag: delivery.etag
        },
        body: response
      };
    }

    const parentRelease =
      selected.parentReleaseId && (await this.store.getReleaseById(selected.parentReleaseId));
    const canSendStoredPatch =
      selected.artifactType === 'patch' &&
      parentRelease &&
      clientPatchVersion === parentRelease.patchRulesVersion;

    if (canSendStoredPatch) {
      response.patchData = this.encodePayload(selected.artifactJson);
      return {
        statusCode: 200,
        headers: {
          ETag: delivery.etag
        },
        body: response
      };
    }

    response.fullData = this.encodePayload(guarded.rules);
    return {
      statusCode: 200,
      headers: {
        ETag: delivery.etag
      },
      body: response
    };
  }

  normalizePatchEnvelope(input) {
    return {
      upsert: deduplicateRulesByIdentity(input.upsert || []),
      deleteRuleIds: input.deleteRuleIds || [],
      deleteRuleKeys: input.deleteRuleKeys || [],
      tombstones: input.tombstones || [],
      priorityAdjustments: input.priorityAdjustments || [],
      noiseKeywords: input.noiseKeywords || { add: [], remove: [] }
    };
  }

  statusForPublish(rolloutStrategy) {
    const strategy = defaultRolloutStrategy(rolloutStrategy);
    return strategy.type === 'immediate' && strategy.stepPercentage >= 100 ? 'published' : 'rolling_out';
  }

  async getLatestRelease() {
    return this.pickLatestRelease(await this.store.listReleases());
  }

  pickLatestRelease(releases) {
    return [...(releases || [])].sort((left, right) => {
      if (left.configVersion === right.configVersion) {
        return Number(right.id) - Number(left.id);
      }
      return Number(right.configVersion) - Number(left.configVersion);
    })[0] || null;
  }

  async activeEmergencyBlocks() {
    const now = this.now().getTime();
    return (await this.store.listEmergencyBlocks()).filter((block) => {
      if (block.status !== 'active') {
        return false;
      }

      if (!block.expiresAt) {
        return true;
      }

      return new Date(block.expiresAt).getTime() > now;
    });
  }

  async shouldServeRollingRelease(release, requestMeta) {
    if (!this.matchesTargetSelector(requestMeta, release.targetSelector)) {
      return false;
    }

    const percentage = this.currentRolloutPercentage(release);
    const cohortKey =
      requestMeta.cohortKey ||
      requestMeta.installId ||
      requestMeta.build ||
      requestMeta.appVersion ||
      'anonymous';
    const bucket = parseInt(sha256Hex(`${release.releaseRef}:${cohortKey}`).slice(0, 8), 16) % 10000;
    return bucket / 100 <= percentage;
  }

  matchesTargetSelector(meta, selector = {}) {
    if (Array.isArray(selector.platforms) && selector.platforms.length > 0) {
      if (!selector.platforms.map((item) => String(item).toLowerCase()).includes(String(meta.platform || '').toLowerCase())) {
        return false;
      }
    }

    if (Array.isArray(selector.channels) && selector.channels.length > 0) {
      if (!selector.channels.includes(meta.channel || '')) {
        return false;
      }
    }

    if (Array.isArray(selector.builds) && selector.builds.length > 0) {
      if (!selector.builds.includes(meta.build || '')) {
        return false;
      }
    }

    if (selector.appVersion && !matchesRange(meta.appVersion || '0', selector.appVersion)) {
      return false;
    }

    return true;
  }

  currentRolloutPercentage(release) {
    const strategy = defaultRolloutStrategy(release.rolloutStrategy);
    if (strategy.type === 'immediate') {
      return 100;
    }

    const elapsedMinutes =
      (this.now().getTime() - new Date(release.publishTime).getTime()) / (60 * 1000);
    if (elapsedMinutes <= 0) {
      return strategy.stepPercentage;
    }

    if (elapsedMinutes >= strategy.durationMinutes) {
      return 100;
    }

    const steps = Math.max(1, Math.ceil(100 / strategy.stepPercentage));
    const minutesPerStep = strategy.durationMinutes / steps;
    const completedSteps = Math.max(1, Math.ceil(elapsedMinutes / minutesPerStep));
    return Math.min(100, completedSteps * strategy.stepPercentage);
  }

  async finalizeExpiredRollouts() {
    const releases = await this.store.listReleases();
    const rolling = releases.filter((item) => item.status === 'rolling_out');
    for (const release of rolling) {
      const strategy = defaultRolloutStrategy(release.rolloutStrategy);
      const elapsedMinutes =
        (this.now().getTime() - new Date(release.publishTime).getTime()) / (60 * 1000);
      if (this.currentRolloutPercentage(release) >= 100 && elapsedMinutes >= strategy.durationMinutes + strategy.bakeMinutes) {
        const published = await this.store.updateRelease(release.id, {
          status: 'published'
        });
        await this.reconcileActiveStatuses(published);
      }
    }
  }

  async reconcileActiveStatuses(nextRelease) {
    const releases = await this.store.listReleases();
    const updates = [];

    for (const release of releases) {
      if (release.id === nextRelease.id) {
        continue;
      }

      if (nextRelease.status === 'published' && ['published', 'rolling_out'].includes(release.status)) {
        updates.push(this.store.updateRelease(release.id, { status: 'retired' }));
      }

      if (nextRelease.status === 'rolling_out' && release.status === 'rolling_out') {
        updates.push(this.store.updateRelease(release.id, { status: 'retired' }));
      }
    }

    await Promise.all(updates);
  }

  encodePayload(payload) {
    if (!this.encryption.enabled) {
      return payload;
    }

    return aesEncryptCFB(
      JSON.stringify(payload),
      this.encryption.key,
      this.encryption.iv
    );
  }
}

module.exports = {
  RuleReleaseService
};
