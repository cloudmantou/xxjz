function compareNumeric(a = 0, b = 0) {
  if (a === b) {
    return 0;
  }

  return a > b ? 1 : -1;
}

function compareSemverLike(left = '', right = '') {
  const normalize = (value) =>
    String(value)
      .split(/[^0-9]+/)
      .filter(Boolean)
      .map((part) => parseInt(part, 10));

  const l = normalize(left);
  const r = normalize(right);
  const length = Math.max(l.length, r.length);

  for (let index = 0; index < length; index += 1) {
    const result = compareNumeric(l[index] || 0, r[index] || 0);
    if (result !== 0) {
      return result;
    }
  }

  return 0;
}

function matchesRange(value, selector) {
  if (!selector) {
    return true;
  }

  if (selector.equals && compareSemverLike(value, selector.equals) !== 0) {
    return false;
  }

  if (selector.min && compareSemverLike(value, selector.min) < 0) {
    return false;
  }

  if (selector.max && compareSemverLike(value, selector.max) > 0) {
    return false;
  }

  if (Array.isArray(selector.prefixes) && selector.prefixes.length > 0) {
    return selector.prefixes.some((prefix) => String(value).startsWith(prefix));
  }

  return true;
}

module.exports = {
  compareNumeric,
  compareSemverLike,
  matchesRange
};
