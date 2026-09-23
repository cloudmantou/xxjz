// 请求认证中间件
// 验证App请求的合法性

const crypto = require('crypto');

/// API密钥（生产环境应从环境变量读取）
const API_KEY = process.env.API_KEY || 'wuyoushu-api-key-2024';
const SIGN_SECRET = process.env.SIGN_SECRET || 'wuyoushu-sign-secret';

/// 签名验证中间件
function authMiddleware(req, res, next) {
  // 开发环境跳过验证
  if (process.env.NODE_ENV === 'development') {
    return next();
  }

  const apiKey = req.headers['x-api-key'];
  const timestamp = req.headers['x-timestamp'];
  const signature = req.headers['x-signature'];

  // 验证API Key
  if (!apiKey || apiKey !== API_KEY) {
    return res.status(401).json({
      code: 401,
      message: 'Invalid API key',
      data: null
    });
  }

  // 验证时间戳（5分钟内有效）
  if (!timestamp) {
    return res.status(401).json({
      code: 401,
      message: 'Missing timestamp',
      data: null
    });
  }

  const now = Math.floor(Date.now() / 1000);
  const requestTime = parseInt(timestamp, 10);
  if (Math.abs(now - requestTime) > 300) {
    return res.status(401).json({
      code: 401,
      message: 'Request expired',
      data: null
    });
  }

  // 验证签名
  if (!signature) {
    return res.status(401).json({
      code: 401,
      message: 'Missing signature',
      data: null
    });
  }

  const expectedSignature = generateSignature(req, timestamp);
  if (signature !== expectedSignature) {
    return res.status(401).json({
      code: 401,
      message: 'Invalid signature',
      data: null
    });
  }

  next();
}

/// 生成请求签名
function generateSignature(req, timestamp) {
  const method = req.method.toUpperCase();
  const path = req.path;
  const body = req.body ? JSON.stringify(req.body) : '';

  const payload = `${method}|${path}|${timestamp}|${body}`;
  return crypto
    .createHmac('sha256', SIGN_SECRET)
    .update(payload)
    .digest('hex');
}

module.exports = { authMiddleware, generateSignature };
