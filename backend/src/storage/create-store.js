const { JSONRuleStore } = require('./json-rule-store');
const { MemoryRuleStore } = require('./memory-rule-store');
const { MySQLRuleStore } = require('./mysql-rule-store');
const { PostgresRuleStore } = require('./postgres-rule-store');

function createRuleStore(options = {}) {
  const driver =
    options.driver ||
    process.env.RULES_STORAGE ||
    (process.env.MYSQL_URL || process.env.MYSQL_HOST
      ? 'mysql'
      : process.env.DATABASE_URL
        ? 'postgres'
        : 'json');

  if (driver === 'memory') {
    return new MemoryRuleStore(options.seed);
  }

  if (driver === 'postgres') {
    return new PostgresRuleStore({
      connectionString: options.connectionString || process.env.DATABASE_URL,
      sqlPath: options.sqlPath,
      migrationsDir: options.migrationsDir
    });
  }

  if (driver === 'mysql') {
    return new MySQLRuleStore({
      connectionString: options.connectionString || process.env.MYSQL_URL,
      host: options.host || process.env.MYSQL_HOST,
      port: options.port || process.env.MYSQL_PORT,
      user: options.user || process.env.MYSQL_USER,
      password: options.password || process.env.MYSQL_PASSWORD,
      database: options.database || process.env.MYSQL_DATABASE,
      sqlPath: options.sqlPath,
      migrationsDir: options.migrationsDir
    });
  }

  return new JSONRuleStore({
    filePath: options.filePath
  });
}

module.exports = {
  createRuleStore
};
