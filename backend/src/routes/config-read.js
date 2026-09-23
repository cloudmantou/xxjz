const express = require('express');

const { aesEncryptCFB } = require('../utils/crypto');

function parseIntHeader(value, fallback = 0) {
  const parsed = Number.parseInt(value || String(fallback), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function shouldEncrypt() {
  return process.env.ENABLE_ENCRYPTION === 'true';
}

function createConfigPayload(configService) {
  const document = configService.getConfigDocument();
  const encrypted = shouldEncrypt();
  const configJSON = JSON.stringify(document.config);

  return {
    version: document.version,
    encrypted,
    data: encrypted
      ? aesEncryptCFB(
          configJSON,
          process.env.AES_KEY || 'your-16byte-key!!',
          process.env.AES_IV || 'your-16byte-iv!!!'
        )
      : configJSON
  };
}

function createConfigGetHandler({ configService }) {
  return (req, res) => {
    const clientVersion = parseIntHeader(req.get('X-Config-Version'));
    const document = configService.getConfigDocument();

    if (clientVersion >= document.version) {
      res.json({
        code: 200,
        message: 'Already up to date',
        data: '',
        version: document.version,
        encrypted: false
      });
      return;
    }

    const payload = createConfigPayload(configService);
    res.json({
      code: 200,
      message: 'success',
      data: payload.data,
      version: payload.version,
      encrypted: payload.encrypted
    });
  };
}

function createConfigReadRouter({ configService }) {
  const router = express.Router();
  const getHandler = createConfigGetHandler({ configService });

  router.get('/get', getHandler);
  router.get('/version', (req, res) => {
    res.json({
      code: 200,
      message: 'success',
      data: {
        version: configService.getConfigDocument().version
      }
    });
  });

  return router;
}

module.exports = {
  createConfigGetHandler,
  createConfigReadRouter
};
