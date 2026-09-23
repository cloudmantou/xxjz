function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

class MemoryRuleStore {
  constructor(seed = {}) {
    this.state = deepClone({
      meta: {
        nextSnapshotId: 1,
        nextPatchId: 1,
        nextReleaseId: 1,
        nextEmergencyId: 1,
        rulesConfigVersion: 0
      },
      snapshots: [],
      patches: [],
      releases: [],
      emergencyBlocks: [],
      ...seed
    });
  }

  async initialize() {}

  async listSnapshots() {
    return deepClone(this.state.snapshots);
  }

  async getSnapshotByRef(snapshotRef) {
    return deepClone(this.state.snapshots.find((item) => item.snapshotRef === snapshotRef) || null);
  }

  async insertSnapshot(snapshot) {
    const next = {
      id: this.state.meta.nextSnapshotId++,
      createdAt: new Date().toISOString(),
      ...deepClone(snapshot)
    };
    this.state.snapshots.push(next);
    return deepClone(next);
  }

  async listPatches() {
    return deepClone(this.state.patches);
  }

  async getPatchByRef(patchRef) {
    return deepClone(this.state.patches.find((item) => item.patchRef === patchRef) || null);
  }

  async insertPatch(patch) {
    const next = {
      id: this.state.meta.nextPatchId++,
      createdAt: new Date().toISOString(),
      ...deepClone(patch)
    };
    this.state.patches.push(next);
    return deepClone(next);
  }

  async listReleases() {
    return deepClone(this.state.releases);
  }

  async getReleaseById(id) {
    return deepClone(this.state.releases.find((item) => String(item.id) === String(id)) || null);
  }

  async getReleaseByRef(releaseRef) {
    return deepClone(this.state.releases.find((item) => item.releaseRef === releaseRef) || null);
  }

  async insertRelease(release) {
    const next = {
      id: this.state.meta.nextReleaseId++,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      ...deepClone(release)
    };
    this.state.releases.push(next);
    return deepClone(next);
  }

  async updateRelease(id, updates) {
    const index = this.state.releases.findIndex((item) => String(item.id) === String(id));
    if (index === -1) {
      return null;
    }

    this.state.releases[index] = {
      ...this.state.releases[index],
      ...deepClone(updates),
      updatedAt: new Date().toISOString()
    };
    return deepClone(this.state.releases[index]);
  }

  async listEmergencyBlocks() {
    return deepClone(this.state.emergencyBlocks);
  }

  async upsertEmergencyBlock(block) {
    const existingIndex = this.state.emergencyBlocks.findIndex(
      (item) => item.fingerprint === block.fingerprint
    );

    const next = {
      id:
        existingIndex >= 0
          ? this.state.emergencyBlocks[existingIndex].id
          : this.state.meta.nextEmergencyId++,
      createdAt:
        existingIndex >= 0
          ? this.state.emergencyBlocks[existingIndex].createdAt
          : new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      status: 'active',
      ...deepClone(block)
    };

    if (existingIndex >= 0) {
      this.state.emergencyBlocks[existingIndex] = next;
    } else {
      this.state.emergencyBlocks.push(next);
    }

    this.state.meta.rulesConfigVersion += 1;
    return deepClone(next);
  }

  async removeEmergencyBlock(fingerprint) {
    const index = this.state.emergencyBlocks.findIndex((item) => item.fingerprint === fingerprint);
    if (index === -1) {
      return false;
    }
    this.state.emergencyBlocks.splice(index, 1);
    this.state.meta.rulesConfigVersion += 1;
    return true;
  }

  async getRuntimeState() {
    return {
      rulesConfigVersion: this.state.meta.rulesConfigVersion
    };
  }

  async setRuntimeState(nextState) {
    this.state.meta.rulesConfigVersion =
      nextState.rulesConfigVersion ?? this.state.meta.rulesConfigVersion;
    return this.getRuntimeState();
  }
}

module.exports = {
  MemoryRuleStore
};
