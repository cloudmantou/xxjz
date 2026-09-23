const express = require('express');

function createConfigAdminRouter({ configService }) {
  const router = express.Router();

  router.post('/update', async (req, res, next) => {
    try {
      const document = await configService.updateConfig(req.body || {});
      res.json({
        code: 200,
        message: 'Config updated',
        data: {
          version: document.version
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/update-ocr-keywords', async (req, res, next) => {
    try {
      const document = await configService.updateOCRKeywords(req.body || {});
      res.json({
        code: 200,
        message: 'OCR keywords updated',
        data: {
          version: document.version,
          ocrVersion: document.config.ocrRegDict?.version || 0
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/update-category-keywords', async (req, res, next) => {
    try {
      const categoryKeywords = req.body?.categoryKeywords;
      if (!categoryKeywords || typeof categoryKeywords !== 'object' || Array.isArray(categoryKeywords)) {
        res.status(400).json({
          code: 400,
          message: 'Invalid categoryKeywords',
          data: null
        });
        return;
      }

      const document = await configService.updateCategoryKeywords(categoryKeywords);
      res.json({
        code: 200,
        message: 'Category keywords updated',
        data: {
          version: document.version,
          ocrVersion: document.config.ocrRegDict?.version || 0
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/update-app-settings', async (req, res, next) => {
    try {
      const appSettings = req.body?.appSettings;
      if (!appSettings || typeof appSettings !== 'object' || Array.isArray(appSettings)) {
        res.status(400).json({
          code: 400,
          message: 'Invalid appSettings',
          data: null
        });
        return;
      }

      const document = await configService.updateConfig({ appSettings });
      res.json({
        code: 200,
        message: 'App settings updated',
        data: {
          version: document.version,
          appSettings: document.config.appSettings || null
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/reset', async (req, res, next) => {
    try {
      const document = await configService.reset();
      res.json({
        code: 200,
        message: 'Config reset to defaults',
        data: {
          version: document.version
        }
      });
    } catch (error) {
      next(error);
    }
  });

  router.get('/export', (req, res) => {
    const document = configService.getConfigDocument();
    res.json({
      code: 200,
      message: 'success',
      data: document
    });
  });

  return router;
}

module.exports = {
  createConfigAdminRouter
};
