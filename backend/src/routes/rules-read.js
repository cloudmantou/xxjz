const express = require('express');

function parseVersionHeader(value) {
  const parsed = Number.parseInt(value || '0', 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function buildRequestMeta(req) {
  return {
    rulesVersion: parseVersionHeader(req.get('X-Rules-Version')),
    rulesConfigVersion: parseVersionHeader(
      req.get('X-Rules-Config-Version') || req.get('X-Config-Version')
    ),
    appVersion: req.get('X-App-Version') || req.get('X-App-Version-Name') || '0',
    build: req.get('X-Build') || req.get('X-App-Build') || '',
    platform: (req.get('X-Platform') || 'ios').toLowerCase(),
    channel: req.get('X-Channel') || '',
    cohortKey: req.get('X-Cohort-Key') || '',
    installId: req.get('X-Install-Id') || '',
    ifNoneMatch: req.get('If-None-Match') || '',
    format:
      req.query.format === 'legacy' || req.get('X-Response-Format') === 'legacy'
        ? 'legacy'
        : 'standard'
  };
}

function createRulesReadRouter({ ruleReleaseService }) {
  const router = express.Router();

  router.get('/List', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.buildReadResponse(buildRequestMeta(req));
      for (const [headerName, headerValue] of Object.entries(result.headers || {})) {
        if (headerValue !== undefined && headerValue !== null && headerValue !== '') {
          res.setHeader(headerName, headerValue);
        }
      }

      if (result.statusCode === 304) {
        res.status(304).end();
        return;
      }

      res.status(result.statusCode || 200).json(result.body);
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = {
  createRulesReadRouter
};
