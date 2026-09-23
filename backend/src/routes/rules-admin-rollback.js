const express = require('express');

function createRulesAdminRollbackRouter({ ruleReleaseService }) {
  const router = express.Router();

  router.post('/rollback', async (req, res, next) => {
    try {
      const result = await ruleReleaseService.rollbackToRelease({
        releaseId: req.body?.releaseId || null,
        releaseRef: req.body?.releaseRef || null,
        note: req.body?.note || null
      });

      if (!result.ok) {
        res.status(result.statusCode || 400).json({
          code: result.statusCode || 400,
          message: result.error || 'rollback_failed',
          details: result.details || []
        });
        return;
      }

      res.status(result.statusCode || 201).json({
        code: 0,
        message: 'success',
        data: result.release
      });
    } catch (error) {
      next(error);
    }
  });

  return router;
}

module.exports = {
  createRulesAdminRollbackRouter
};
