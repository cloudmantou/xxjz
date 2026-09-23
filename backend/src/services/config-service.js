const fs = require('fs');
const path = require('path');

const defaultConfig = require('../config/default');

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

class ConfigService {
  constructor(options = {}) {
    this.filePath =
      options.filePath || path.join(process.cwd(), 'backend', 'data', 'config-document.json');
    this.currentConfig = deepClone(defaultConfig);
    this.version = 1;
  }

  async initialize() {
    await fs.promises.mkdir(path.dirname(this.filePath), { recursive: true });

    try {
      const raw = await fs.promises.readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw);
      this.currentConfig = parsed.config || deepClone(defaultConfig);
      this.version = parsed.version || 1;
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
      await this.persist();
    }
  }

  getConfigDocument() {
    return {
      config: deepClone(this.currentConfig),
      version: this.version
    };
  }

  async updateConfig(partialConfig) {
    const { ocrRegDict, shortcutTemplates, categories, appSettings, featureFlags } = partialConfig;

    if (ocrRegDict) {
      this.currentConfig.ocrRegDict = { ...this.currentConfig.ocrRegDict, ...ocrRegDict };
    }

    if (shortcutTemplates) {
      this.currentConfig.shortcutTemplates = shortcutTemplates;
    }

    if (categories) {
      this.currentConfig.categories = categories;
    }

    if (appSettings) {
      this.currentConfig.appSettings = {
        ...(this.currentConfig.appSettings || {}),
        ...appSettings
      };
    }

    if (featureFlags) {
      this.currentConfig.featureFlags = {
        ...(this.currentConfig.featureFlags || {}),
        ...featureFlags
      };
    }

    this.version += 1;
    await this.persist();
    return this.getConfigDocument();
  }

  async updateOCRKeywords(partial) {
    this.currentConfig.ocrRegDict = {
      ...(this.currentConfig.ocrRegDict || {}),
      ...partial,
      version: (this.currentConfig.ocrRegDict?.version || 0) + 1
    };
    this.version += 1;
    await this.persist();
    return this.getConfigDocument();
  }

  async updateCategoryKeywords(categoryKeywords) {
    this.currentConfig.ocrRegDict = this.currentConfig.ocrRegDict || {};
    this.currentConfig.ocrRegDict.categoryKeywords = {
      ...(this.currentConfig.ocrRegDict.categoryKeywords || {}),
      ...categoryKeywords
    };
    this.currentConfig.ocrRegDict.version = (this.currentConfig.ocrRegDict.version || 0) + 1;
    this.version += 1;
    await this.persist();
    return this.getConfigDocument();
  }

  async reset() {
    this.currentConfig = deepClone(defaultConfig);
    this.version += 1;
    await this.persist();
    return this.getConfigDocument();
  }

  async persist() {
    await fs.promises.writeFile(
      this.filePath,
      JSON.stringify(
        {
          version: this.version,
          config: this.currentConfig
        },
        null,
        2
      ),
      'utf8'
    );
  }
}

module.exports = {
  ConfigService
};
