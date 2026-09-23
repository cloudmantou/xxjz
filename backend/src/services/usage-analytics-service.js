const fs = require('fs');
const path = require('path');

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function safeString(value, fallback = '') {
  if (typeof value !== 'string') {
    return fallback;
  }
  return value.trim();
}

function safeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

class UsageAnalyticsService {
  constructor(options = {}) {
    const maxEventsFromEnv = Number.parseInt(process.env.USAGE_ANALYTICS_MAX_EVENTS || '', 10);
    this.maxEvents = Number.isFinite(maxEventsFromEnv)
      ? Math.max(100, maxEventsFromEnv)
      : Math.max(100, safeNumber(options.maxEvents, 5000));

    this.filePath =
      options.filePath || path.join(process.cwd(), 'backend', 'data', 'usage-analytics.json');

    this.state = {
      totalRequestCount: 0,
      users: {},
      events: []
    };

    this.persistTimer = null;
  }

  async initialize() {
    await fs.promises.mkdir(path.dirname(this.filePath), { recursive: true });
    try {
      const raw = await fs.promises.readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw);
      this.state = {
        totalRequestCount: safeNumber(parsed.totalRequestCount, 0),
        users: parsed.users && typeof parsed.users === 'object' ? parsed.users : {},
        events: Array.isArray(parsed.events) ? parsed.events : []
      };
      this.trimEvents();
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
      await this.persist();
    }
  }

  recordRequest({ req, statusCode, durationMs }) {
    if (!req?.originalUrl || !req.originalUrl.startsWith('/api/')) {
      return;
    }

    const nowISO = new Date().toISOString();
    const installId = safeString(req.get('X-Install-Id'));
    const userAgent = safeString(req.get('User-Agent'));
    const platform = safeString(req.get('X-Platform'), 'unknown');
    const appVersion = safeString(req.get('X-App-Version'), 'unknown');
    const build = safeString(req.get('X-Build'), 'unknown');
    const channel = safeString(req.get('X-Channel'), 'unknown');
    const configVersion = safeString(req.get('X-Config-Version'));
    const rulesVersion = safeString(req.get('X-Rules-Version'));
    const ip =
      safeString(req.get('x-forwarded-for')).split(',')[0]?.trim() ||
      req.ip ||
      req.socket?.remoteAddress ||
      'unknown';

    const userKey = installId || `${ip}::${userAgent || 'unknown'}`;
    const existingUser = this.state.users[userKey];
    if (existingUser) {
      existingUser.lastSeenAt = nowISO;
      existingUser.requestCount = safeNumber(existingUser.requestCount, 0) + 1;
      if (!existingUser.installId && installId) {
        existingUser.installId = installId;
      }
    } else {
      this.state.users[userKey] = {
        userKey,
        installId: installId || null,
        firstSeenAt: nowISO,
        lastSeenAt: nowISO,
        requestCount: 1,
        platform,
        appVersion
      };
    }

    const event = {
      time: nowISO,
      method: req.method,
      path: req.path,
      statusCode: safeNumber(statusCode, 0),
      durationMs: Math.max(0, Math.round(safeNumber(durationMs, 0))),
      userKey,
      installId: installId || null,
      platform,
      appVersion,
      build,
      channel,
      configVersion: configVersion || null,
      rulesVersion: rulesVersion || null
    };

    this.state.events.push(event);
    this.state.totalRequestCount += 1;
    this.trimEvents();
    this.schedulePersist();
  }

  getSummary({ configDocument, recentEventLimit = 80, activeWindowHours = 24 } = {}) {
    const now = Date.now();
    const cutoff = now - Math.max(1, activeWindowHours) * 60 * 60 * 1000;
    const users = Object.values(this.state.users || {});
    const activeUsers = users.filter((user) => Date.parse(user.lastSeenAt || '') >= cutoff);
    const recentEvents = this.getRecentEvents(recentEventLimit);
    const last24hEvents = this.state.events.filter(
      (event) => Date.parse(event.time || '') >= cutoff
    );

    const routeCounter = {};
    const platformCounter = {};
    for (const event of last24hEvents) {
      const routeKey = `${event.method} ${event.path}`;
      routeCounter[routeKey] = (routeCounter[routeKey] || 0) + 1;
      platformCounter[event.platform || 'unknown'] =
        (platformCounter[event.platform || 'unknown'] || 0) + 1;
    }

    const topRoutes = Object.entries(routeCounter)
      .sort((left, right) => right[1] - left[1])
      .slice(0, 8)
      .map(([route, count]) => ({ route, count }));

    const bookkeepingParams = configDocument?.config || null;

    return {
      generatedAt: new Date().toISOString(),
      users: {
        total: users.length,
        active24h: activeUsers.length
      },
      traffic: {
        totalRequests: this.state.totalRequestCount,
        requests24h: last24hEvents.length,
        topRoutes,
        platformBreakdown: platformCounter
      },
      recentEvents,
      bookkeepingParams
    };
  }

  getRecentEvents(limit = 100) {
    const safeLimit = Math.max(1, Math.min(500, Number.parseInt(String(limit), 10) || 100));
    return this.state.events.slice(-safeLimit).reverse();
  }

  trimEvents() {
    if (this.state.events.length > this.maxEvents) {
      this.state.events = this.state.events.slice(this.state.events.length - this.maxEvents);
    }
  }

  schedulePersist() {
    if (this.persistTimer) {
      return;
    }
    this.persistTimer = setTimeout(async () => {
      this.persistTimer = null;
      try {
        await this.persist();
      } catch (error) {
        // Keep non-blocking in request lifecycle
        // eslint-disable-next-line no-console
        console.error('[UsageAnalyticsPersistError]', error);
      }
    }, 300);
  }

  async persist() {
    const payload = deepClone(this.state);
    await fs.promises.writeFile(this.filePath, JSON.stringify(payload, null, 2), 'utf8');
  }
}

module.exports = {
  UsageAnalyticsService
};
