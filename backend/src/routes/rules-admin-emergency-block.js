const express = require('express');

function decodeFingerprint(value) {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

function createRulesAdminEmergencyBlockRouter({ ruleReleaseService }) {
  const router = express.Router();

  router.get('/emergency-blocks', async (req, res, next) => {
    try {
      const blocks = await ruleReleaseService.listEmergencyBlocks();
      res.json({
        code: 0,
        message: 'success',
        data: blocks
      });
    } catch (error) {
      next(error);
    }
  });

  router.post('/emergency-blocks', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.addEmergencyBlock(req.body || {});
      if (!result.ok) {
        res.status(result.statusCode || 400).json({
          code: result.statusCode || 400,
          message: result.error || 'emergency_block_failed',
          data: null
        });
        return;
      }

      res.status(result.statusCode || 201).json({
        code: 0,
        message: 'success',
        data: result.block
      });
    } catch (error) {
      next(error);
    }
  });

  router.delete('/emergency-blocks/:fingerprint', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.removeEmergencyBlock(
        decodeFingerprint(req.params.fingerprint)
      );
      if (!result.ok) {
        res.status(result.statusCode || 404).json({
          code: result.statusCode || 404,
          message: 'emergency_block_not_found',
          data: null
        });
        return;
      }

      res.json({
        code: 0,
        message: 'success',
        data: true
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = {
  createRulesAdminEmergencyBlockRouter
};
