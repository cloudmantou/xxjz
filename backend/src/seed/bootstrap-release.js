function createSearchText(ruleId, billSource, ruleKind = 0, minMatchValue = 0.58) {
  return {
    index: 0,
    ruleId,
    ruleKind,
    billSource,
    minMatchValue,
    matchType: 2,
    isFuzzy: true,
    isFuzzyLastValue: false,
    isOptional: false,
    isMutableLine: false,
    columnCount: 1,
    alignment: 0,
    candidateType: 2,
    subCandidateType: 0
  };
}

function createRule({
  ruleId,
  keyWord,
  type,
  memberCateId,
  keyWordSource,
  fundAccountId,
  billSource,
  ruleKind = 0,
  minMatchValue = 0.58
}) {
  return {
    ruleId,
    keyWord,
    memberId: null,
    type,
    memberCateId,
    billsBookId: 0,
    keyWordSource,
    fundAccountId,
    memberTagIds: null,
    createDate: null,
    updateDate: null,
    searchTexts: [createSearchText(ruleId, billSource, ruleKind, minMatchValue)]
  };
}

function buildBootstrapRules() {
  return [
    createRule({
      ruleId: 1001,
      keyWord: '外卖',
      type: 1,
      memberCateId: 101,
      keyWordSource: 0,
      fundAccountId: 2,
      billSource: 2
    }),
    createRule({
      ruleId: 1002,
      keyWord: '美团',
      type: 1,
      memberCateId: 101,
      keyWordSource: 0,
      fundAccountId: 2,
      billSource: 2
    }),
    createRule({
      ruleId: 1003,
      keyWord: '星巴克',
      type: 1,
      memberCateId: 101,
      keyWordSource: 4,
      fundAccountId: 1,
      billSource: 1
    }),
    createRule({
      ruleId: 1101,
      keyWord: '滴滴',
      type: 1,
      memberCateId: 201,
      keyWordSource: 0,
      fundAccountId: 2,
      billSource: 2
    }),
    createRule({
      ruleId: 1102,
      keyWord: '地铁',
      type: 1,
      memberCateId: 201,
      keyWordSource: 4,
      fundAccountId: 1,
      billSource: 1
    }),
    createRule({
      ruleId: 1201,
      keyWord: '工资',
      type: 2,
      memberCateId: 901,
      keyWordSource: 6,
      fundAccountId: 1,
      billSource: 1
    }),
    createRule({
      ruleId: 1202,
      keyWord: '报销',
      type: 2,
      memberCateId: 903,
      keyWordSource: 2,
      fundAccountId: 2,
      billSource: 2
    }),
    createRule({
      ruleId: 1301,
      keyWord: '转账',
      type: 5,
      memberCateId: 801,
      keyWordSource: 3,
      fundAccountId: 2,
      billSource: 2,
      ruleKind: 1,
      minMatchValue: 0.72
    }),
    createRule({
      ruleId: 1401,
      keyWord: '话费充值',
      type: 1,
      memberCateId: 601,
      keyWordSource: 4,
      fundAccountId: 1,
      billSource: 1,
      ruleKind: 1
    }),
    createRule({
      ruleId: 1501,
      keyWord: '超市',
      type: 1,
      memberCateId: 301,
      keyWordSource: 4,
      fundAccountId: 1,
      billSource: 1
    })
  ];
}

function buildBootstrapReleaseInput(note = 'bootstrap seed release') {
  return {
    rules: buildBootstrapRules(),
    publish: true,
    note,
    rolloutStrategy: {
      type: 'immediate',
      percentage: 100,
      stepPercentage: 100,
      durationMinutes: 1,
      bakeMinutes: 0
    },
    targetSelector: {
      platforms: ['ios'],
      channels: [],
      builds: [],
      appVersion: {}
    }
  };
}

module.exports = {
  buildBootstrapReleaseInput,
  buildBootstrapRules
};
