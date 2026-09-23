const cors = require('cors');
const express = require('express');
const helmet = require('helmet');
const path = require('path');

const { createAdminDashboardRouter } = require('./routes/admin-dashboard');
const { authMiddleware } = require('./middleware/auth');
const { createConfigAdminRouter } = require('./routes/config-admin');
const { createConfigGetHandler, createConfigReadRouter } = require('./routes/config-read');
const {
  createRulesAdminEmergencyBlockRouter
} = require('./routes/rules-admin-emergency-block');
const { createRulesAdminPublishRouter } = require('./routes/rules-admin-publish');
const { createRulesAdminRollbackRouter } = require('./routes/rules-admin-rollback');
const { createRulesReadRouter } = require('./routes/rules-read');
const { ConfigService } = require('./services/config-service');
const { RuleReleaseService } = require('./services/rule-release-service');
const { UsageAnalyticsService } = require('./services/usage-analytics-service');
const { createRuleStore } = require('./storage/create-store');

async function initializeService(service) {
  if (service && typeof service.initialize === 'function') {
    await service.initialize();
  }
}

async function createApp(options = {}) {
  const logger = options.logger || console;
  const configService =
    options.configService || new ConfigService(options.configServiceOptions || {});
  const ruleReleaseService =
    options.ruleReleaseService ||
    new RuleReleaseService({
      store: options.ruleStore || createRuleStore(options.ruleStoreOptions || {}),
      logger,
      enableEncryption: options.enableEncryption,
      aesKey: options.aesKey,
      aesIV: options.aesIV
    });
  const usageAnalyticsService =
    options.usageAnalyticsService ||
    new UsageAnalyticsService(options.usageAnalyticsServiceOptions || {});

  await initializeService(configService);
  await initializeService(ruleReleaseService);
  await initializeService(usageAnalyticsService);

  const app = express();
  app.locals.services = {
    configService,
    ruleReleaseService,
    usageAnalyticsService
  };

  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: true }));

  app.use((req, res, next) => {
    const startedAt = Date.now();
    res.on('finish', () => {
      const durationMs = Date.now() - startedAt;
      usageAnalyticsService.recordRequest({
        req,
        statusCode: res.statusCode,
        durationMs
      });

      logger.log?.(
        `[${new Date().toISOString()}] ${req.method} ${req.originalUrl} ${res.statusCode} ${durationMs}ms`
      );
    });
    next();
  });

  app.get('/privacy', (req, res) => {
    res.sendFile(path.join(__dirname, 'static', 'privacy.html'));
  });

  app.get('/health', async (req, res, next) => {
    try {
      const releases = await ruleReleaseService.listReleases();
      res.json({
        status: 'ok',
        time: new Date().toISOString(),
        configVersion: configService.getConfigDocument().version,
        releaseCount: releases.length
      });
    } catch (error) {
      next(error);
    }
  });

  app.use('/api/config', createConfigReadRouter({ configService }));
  app.get('/api/Config/GetV2', createConfigGetHandler({ configService }));

  app.use('/api/config', authMiddleware, createConfigAdminRouter({ configService }));
  app.use('/api/KeyWordMatchingRule', createRulesReadRouter({ ruleReleaseService }));
  app.use(
    '/api/admin/rules',
    authMiddleware,
    createRulesAdminPublishRouter({ ruleReleaseService }),
    createRulesAdminRollbackRouter({ ruleReleaseService }),
    createRulesAdminEmergencyBlockRouter({ ruleReleaseService })
  );

  app.use(
    '/admin',
    createAdminDashboardRouter({
      configService,
      ruleReleaseService,
      usageAnalyticsService
    })
  );

  app.use((req, res) => {
    res.status(404).json({
      code: 404,
      message: 'Not found',
      data: null
    });
  });

  app.use((error, req, res, next) => {
    logger.error?.('[BackendError]', error);
    res.status(500).json({
      code: 500,
      message: 'Internal server error',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined,
      data: null
    });
  });

  return app;
}

module.exports = {
  createApp
};
