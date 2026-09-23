const fs = require('fs');
const path = require('path');

const { MemoryRuleStore } = require('./memory-rule-store');

class JSONRuleStore extends MemoryRuleStore {
  constructor(options = {}) {
    super();
    this.filePath =
      options.filePath || path.join(process.cwd(), 'backend', 'data', 'rules-store.json');
  }

  async initialize() {
    await fs.promises.mkdir(path.dirname(this.filePath), { recursive: true });
    try {
      const raw = await fs.promises.readFile(this.filePath, 'utf8');
      this.state = JSON.parse(raw);
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
      await this.persist();
    }
  }

  async insertSnapshot(snapshot) {
    const result = await super.insertSnapshot(snapshot);
    await this.persist();
    return result;
  }

  async insertPatch(patch) {
    const result = await super.insertPatch(patch);
    await this.persist();
    return result;
  }

  async insertRelease(release) {
    const result = await super.insertRelease(release);
    await this.persist();
    return result;
  }

  async updateRelease(id, updates) {
    const result = await super.updateRelease(id, updates);
    await this.persist();
    return result;
  }

  async upsertEmergencyBlock(block) {
    const result = await super.upsertEmergencyBlock(block);
    await this.persist();
    return result;
  }

  async removeEmergencyBlock(fingerprint) {
    const result = await super.removeEmergencyBlock(fingerprint);
    await this.persist();
    return result;
  }

  async setRuntimeState(nextState) {
    const result = await super.setRuntimeState(nextState);
    await this.persist();
    return result;
  }

  async persist() {
    await fs.promises.writeFile(this.filePath, JSON.stringify(this.state, null, 2), 'utf8');
  }
}

module.exports = {
  JSONRuleStore
};
