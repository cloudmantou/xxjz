const express = require('express');

function normalizeJSONValue(value) {
  if (typeof value !== 'string') {
    return value;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return value;
  }

  try {
    return JSON.parse(trimmed);
  } catch (error) {
    return value;
  }
}

function extractRules(body) {
  const candidate =
    normalizeJSONValue(body.rules) ??
    normalizeJSONValue(body.fullRules) ??
    normalizeJSONValue(body.fullData) ??
    normalizeJSONValue(body.data);

  return Array.isArray(candidate) ? candidate : null;
}

function extractPatchEnvelope(body) {
  const patch = normalizeJSONValue(body.patch);
  if (patch && typeof patch === 'object' && !Array.isArray(patch)) {
    return patch;
  }

  return {
    upsert: normalizeJSONValue(body.upsert) || normalizeJSONValue(body.rules) || [],
    deleteRuleIds: normalizeJSONValue(body.deleteRuleIds) || [],
    deleteRuleKeys: normalizeJSONValue(body.deleteRuleKeys) || [],
    tombstones: normalizeJSONValue(body.tombstones) || [],
    priorityAdjustments: normalizeJSONValue(body.priorityAdjustments) || [],
    noiseKeywords: normalizeJSONValue(body.noiseKeywords) || { add: [], remove: [] }
  };
}

function normalizeBoolean(value, fallback = true) {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'string') {
    return !['0', 'false', 'no'].includes(value.trim().toLowerCase());
  }
  return Boolean(value);
}

function sendServiceResult(res, result, successStatusCode = 200) {
  if (!result.ok) {
    res.status(result.statusCode || 400).json({
      code: result.statusCode || 400,
      message: result.error || 'request_failed',
      details: result.details || []
    });
    return;
  }

  res.status(result.statusCode || successStatusCode).json({
    code: 0,
    message: 'success',
    data: result.release || result.releases || null
  });
}

function createRulesAdminPublishRouter({ ruleReleaseService }) {
  const router = express.Router();

  router.get('/releases', async (req, res, next) => {
    try {
      const releases = await ruleReleaseService.listReleases();
      res.json({
        code: 0,
        message: 'success',
        data: releases
      });
    } catch (error) {
      next(error);
    }
  });

  router.get('/releases/:id', async (req, res, next) => {
    try {
      const release = await ruleReleaseService.getRelease(req.params.id);
      if (!release) {
        res.status(404).json({
          code: 404,
          message: 'release_not_found',
          data: null
        });
        return;
      }

      res.json({
        code: 0,
        message: 'success',
        data: release
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/releases/full', async (req, res, next) => {
    try {
      const rules = extractRules(req.body || {});
      if (!rules) {
        res.status(400).json({
          code: 400,
          message: 'rules must be an array',
          data: null
        });
        return;
      }

      const result = await ruleReleaseService.createFullReleaseDraft({
        rules,
        publish: normalizeBoolean(req.body?.publish, true),
        note: req.body?.note || null,
        rolloutStrategy: normalizeJSONValue(req.body?.rolloutStrategy) || req.body?.rolloutStrategy,
        targetSelector: normalizeJSONValue(req.body?.targetSelector) || req.body?.targetSelector
      });
      sendServiceResult(res, result, 201);
    } catch (error) {
      next(error);
    }
  });

  router.post('/releases/patch', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.createPatchReleaseDraft({
        patch: extractPatchEnvelope(req.body || {}),
        publish: normalizeBoolean(req.body?.publish, true),
        note: req.body?.note || null,
        baseReleaseId: req.body?.baseReleaseId || null,
        rolloutStrategy: normalizeJSONValue(req.body?.rolloutStrategy) || req.body?.rolloutStrategy,
        targetSelector: normalizeJSONValue(req.body?.targetSelector) || req.body?.targetSelector
      });
      sendServiceResult(res, result, 201);
    } catch (error) {
      next(error);
    }
  });

  router.post('/releases/:id/publish', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.publishRelease(req.params.id, {
        note: req.body?.note || null,
        rolloutStrategy: normalizeJSONValue(req.body?.rolloutStrategy) || req.body?.rolloutStrategy,
        targetSelector: normalizeJSONValue(req.body?.targetSelector) || req.body?.targetSelector
      });
      sendServiceResult(res, result);
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = {
  createRulesAdminPublishRouter
};
