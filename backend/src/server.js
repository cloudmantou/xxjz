const { createApp } = require('./app');

const PORT = process.env.PORT || 9090;

async function start() {
  const app = await createApp();
  app.listen(PORT, () => {
    console.log(`[ConfigServer] Running on port ${PORT}`);
    console.log(`[ConfigServer] Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(
      `[ConfigServer] Encryption: ${process.env.ENABLE_ENCRYPTION === 'true' ? 'enabled' : 'disabled'}`
    );
  });
}

start().catch((error) => {
  console.error('[StartupError]', error);
  process.exitCode = 1;
});
