const Ajv2020 = require('ajv/dist/2020');

const ruleSchema = require('../schemas/rule.schema.json');
const patchSchema = require('../schemas/rule-patch.schema.json');
const {
  buildRuleIdentity,
  identityFingerprint,
  normalizeTombstones
} = require('./rule-merge');

class RuleValidator {
  constructor() {
    const ajv = new Ajv2020({
      allErrors: true,
      strict: false
    });
    ajv.addSchema(ruleSchema, 'rule.schema.json');
    this.validateRule = ajv.compile(ruleSchema);
    this.validatePatch = ajv.compile(patchSchema);
  }

  validateRules(rules) {
    if (!Array.isArray(rules) || rules.length === 0) {
      return {
        valid: false,
        errors: ['rules must be a non-empty array']
      };
    }

    const schemaErrors = [];
    for (const [index, rule] of rules.entries()) {
      if (!this.validateRule(rule)) {
        for (const error of this.validateRule.errors || []) {
          schemaErrors.push(`rules[${index}] ${error.instancePath || '/'} ${error.message}`);
        }
      }
    }

    const domainErrors = [];
    const seenRuleIds = new Set();
    const seenFingerprints = new Set();

    for (const [index, rule] of rules.entries()) {
      const trimmedKeyword = String(rule.keyWord || '').trim();
      if (!trimmedKeyword) {
        domainErrors.push(`rules[${index}] keyWord must not be blank`);
      }

      if (seenRuleIds.has(Number(rule.ruleId))) {
        domainErrors.push(`duplicate ruleId ${rule.ruleId}`);
      } else {
        seenRuleIds.add(Number(rule.ruleId));
      }

      const fingerprint = identityFingerprint(buildRuleIdentity(rule));
      if (seenFingerprints.has(fingerprint)) {
        domainErrors.push(`duplicate rule identity ${fingerprint}`);
      } else {
        seenFingerprints.add(fingerprint);
      }

      if (Array.isArray(rule.searchTexts)) {
        for (const [searchIndex, item] of rule.searchTexts.entries()) {
          if (Number(item.ruleId) !== Number(rule.ruleId)) {
            domainErrors.push(
              `rules[${index}].searchTexts[${searchIndex}] ruleId ${item.ruleId} does not match parent ${rule.ruleId}`
            );
          }
        }
      }
    }

    return {
      valid: schemaErrors.length === 0 && domainErrors.length === 0,
      errors: [...schemaErrors, ...domainErrors]
    };
  }

  validatePatchEnvelope(patch) {
    if (!this.validatePatch(patch)) {
      return {
        valid: false,
        errors: (this.validatePatch.errors || []).map(
          (error) => `${error.instancePath || '/'} ${error.message}`
        )
      };
    }

    const tombstones = normalizeTombstones(patch.tombstones || []);
    const duplicateDeleteIds = new Set();
    const errors = [];

    for (const ruleId of patch.deleteRuleIds || []) {
      if (duplicateDeleteIds.has(Number(ruleId))) {
        errors.push(`duplicate deleteRuleId ${ruleId}`);
      } else {
        duplicateDeleteIds.add(Number(ruleId));
      }
    }

    for (const tombstone of tombstones) {
      if (!Number.isFinite(Number(tombstone.identity.ruleId))) {
        errors.push(`invalid tombstone identity ${JSON.stringify(tombstone.identity)}`);
      }
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }
}

module.exports = {
  RuleValidator
};
