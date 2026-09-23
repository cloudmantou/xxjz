const express = require('express');
const path = require('path');

function normalizeProfileLinks(input) {
  if (!Array.isArray(input)) {
    return [];
  }

  return input
    .map((item, index) => {
      if (!item || typeof item !== 'object' || Array.isArray(item)) {
        return null;
      }

      const name = String(item.name || '').trim();
      const url = String(item.url || '').trim();
      if (!name || !url) {
        return null;
      }

      const id = String(item.id || '').trim() || `link-${index + 1}`;
      const platform = String(item.platform || '').trim() || 'custom';
      const symbolName = String(item.symbolName || '').trim() || null;
      const enabled = typeof item.enabled === 'boolean' ? item.enabled : true;
      const openInExternalBrowser =
        typeof item.openInExternalBrowser === 'boolean' ? item.openInExternalBrowser : true;

      return {
        id,
        name,
        platform,
        url,
        enabled,
        symbolName,
        openInExternalBrowser
      };
    })
    .filter(Boolean);
}

function resolveAdminToken(req) {
  const queryToken = req.query?.token;
  if (typeof queryToken === 'string' && queryToken.trim()) {
    return queryToken.trim();
  }

  const headerToken = req.get('x-admin-token');
  if (typeof headerToken === 'string' && headerToken.trim()) {
    return headerToken.trim();
  }

  const authHeader = req.get('authorization') || '';
  if (authHeader.startsWith('Bearer ')) {
    return authHeader.replace(/^Bearer\s+/i, '').trim();
  }

  return '';
}

function createAdminPanelAuthMiddleware() {
  return (req, res, next) => {
    if (process.env.NODE_ENV === 'development') {
      return next();
    }

    const expectedToken = process.env.ADMIN_PANEL_TOKEN || process.env.API_KEY;
    if (!expectedToken) {
      return res.status(500).json({
        code: 500,
        message: 'ADMIN_PANEL_TOKEN not configured',
        data: null
      });
    }

    const incomingToken = resolveAdminToken(req);
    if (incomingToken !== expectedToken) {
      if (req.path.startsWith('/api/')) {
        return res.status(401).json({
          code: 401,
          message: 'Invalid admin token',
          data: null
        });
      }

      return res.status(401).type('text/plain; charset=utf-8').send('Unauthorized');
    }

    return next();
  };
}

function createAdminDashboardRouter({
  configService,
  ruleReleaseService,
  usageAnalyticsService
}) {
  const router = express.Router();
  const auth = createAdminPanelAuthMiddleware();
  const adminHTMLPath = path.join(__dirname, '..', 'static', 'admin.html');

  router.use(auth);

  router.get('/', (req, res) => {
    res.sendFile(adminHTMLPath);
  });

  router.get('/api/summary', async (req, res, next) => {
    try {
      const configDocument = configService.getConfigDocument();
      const releases = await ruleReleaseService.listReleases();
      const latestRelease = releases[releases.length - 1] || null;

      const summary = usageAnalyticsService.getSummary({
        configDocument,
        recentEventLimit: Number.parseInt(req.query?.limit || '80', 10) || 80
      });

      res.json({
        code: 200,
        message: 'success',
        data: {
          domain: process.env.APP_PUBLIC_BASE_URL || 'https://xx.cloudmantoua.top',
          backendPort: Number.parseInt(process.env.PORT || '9090', 10),
          configVersion: configDocument.version,
          latestRuleRelease: latestRelease
            ? {
                id: latestRelease.id,
                kind: latestRelease.kind,
                configVersion: latestRelease.configVersion,
                publishTime: latestRelease.publishTime
              }
            : null,
          ...summary
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.get('/api/events', (req, res) => {
    const limit = Number.parseInt(req.query?.limit || '120', 10) || 120;
    const data = usageAnalyticsService.getRecentEvents(limit);
    res.json({
      code: 200,
      message: 'success',
      data
    });
  });

  router.post('/api/config/privacy-policy', async (req, res, next) => {
    try {
      const privacyPolicyURL = String(req.body?.privacyPolicyURL || '').trim();
      if (!privacyPolicyURL) {
        return res.status(400).json({
          code: 400,
          message: 'privacyPolicyURL is required',
          data: null
        });
      }

      const document = await configService.updateConfig({
        appSettings: {
          ...(configService.getConfigDocument().config.appSettings || {}),
          privacyPolicyURL
        }
      });

      return res.json({
        code: 200,
        message: 'Privacy policy URL updated',
        data: {
          version: document.version,
          privacyPolicyURL
        }
      });
    } catch (error) {
      return next(error);
    }
  });

  router.post('/api/config/profile-links', async (req, res, next) => {
    try {
      const profileLinks = normalizeProfileLinks(req.body?.profileLinks);
      const document = await configService.updateConfig({
        appSettings: {
          ...(configService.getConfigDocument().config.appSettings || {}),
          profileLinks
        }
      });

      return res.json({
        code: 200,
        message: 'Profile links updated',
        data: {
          version: document.version,
          profileLinks
        }
      });
    } catch (error) {
      return next(error);
    }
  });

  return router;
}

module.exports = {
  createAdminDashboardRouter
};
