module.exports = (output, { vars }) => {
  const normalized = String(output || '').toLowerCase();
  const parseList = (value, fallback) => {
    if (Array.isArray(value)) {
      return value;
    }
    if (typeof value === 'string' && value.trim()) {
      try {
        const parsed = JSON.parse(value);
        return Array.isArray(parsed) ? parsed : fallback;
      } catch {
        return fallback;
      }
    }
    return fallback;
  };
  const includeGroups = parseList(vars.must_include_any_json || vars.must_include_any, []);
  const avoidTerms = parseList(vars.must_avoid_json || vars.must_avoid, []);

  const missingGroups = includeGroups.filter((group) => {
    return !group.some((term) => normalized.includes(String(term).toLowerCase()));
  });
  const avoidHits = avoidTerms.filter((term) => {
    return normalized.includes(String(term).toLowerCase());
  });

  const includeScore = includeGroups.length === 0
    ? 1
    : (includeGroups.length - missingGroups.length) / includeGroups.length;
  const avoidPenalty = avoidHits.length * 0.12;
  const score = Math.max(0, includeScore - avoidPenalty);
  const pass = missingGroups.length === 0 && avoidHits.length === 0;

  const reasonParts = [];
  if (missingGroups.length > 0) {
    reasonParts.push(`missing include groups: ${missingGroups.map((g) => `[${g.join(' | ')}]`).join(', ')}`);
  }
  if (avoidHits.length > 0) {
    reasonParts.push(`avoid hits: ${avoidHits.join(', ')}`);
  }

  return {
    pass,
    score,
    reason: pass ? 'profile grounding checks passed' : reasonParts.join('; '),
  };
};
