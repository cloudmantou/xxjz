const crypto = require('crypto');

function sha256Hex(value) {
  const input = Buffer.isBuffer(value) ? value : Buffer.from(String(value), 'utf8');
  return crypto.createHash('sha256').update(input).digest('hex');
}

function stableJSONStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableJSONStringify(item)).join(',')}]`;
  }

  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${stableJSONStringify(value[key])}`).join(',')}}`;
  }

  return JSON.stringify(value);
}

function createRulesChecksum(rules) {
  return sha256Hex(stableJSONStringify(rules));
}

function toQuotedETag(value) {
  return `"${String(value).replace(/"/g, '')}"`;
}

function normalizeETag(value) {
  if (!value) {
    return null;
  }

  return String(value).trim().replace(/^W\//i, '').replace(/^"/, '').replace(/"$/, '');
}

function generateStablePercentage(seed, salt = 'wuyoushu-rules') {
  const hash = sha256Hex(`${salt}:${seed}`);
  const bucket = parseInt(hash.slice(0, 8), 16);
  return (bucket % 10000) / 100;
}

function aesEncryptCFB(plaintext, key, iv) {
  const cipher = crypto.createCipheriv('aes-128-cfb', key, iv);
  let encrypted = cipher.update(plaintext, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return encrypted;
}

function aesDecryptCFB(ciphertext, key, iv) {
  const decipher = crypto.createDecipheriv('aes-128-cfb', key, iv);
  let decrypted = decipher.update(ciphertext, 'base64', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

module.exports = {
  aesDecryptCFB,
  aesEncryptCFB,
  createRulesChecksum,
  generateStablePercentage,
  normalizeETag,
  sha256Hex,
  stableJSONStringify,
  toQuotedETag
};
