/* Resolve only plans explicitly configured and approved by QC. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.IqcAqlPlan = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  function resolve(config, group, lotSize) {
    if (!config || config.approved !== true || !config.version || !config.source ||
        !config.level || !config.aql || !config.method || !Number.isSafeInteger(lotSize) || lotSize < 1 ||
        !Array.isArray(config.groups) || !config.groups.includes(group) ||
        !Array.isArray(config.lotRanges) || !config.plans || typeof config.plans !== 'object') return null;
    const matches = config.lotRanges.filter(r => Number.isSafeInteger(r.min) && r.min > 0 &&
      (r.max === null || (Number.isSafeInteger(r.max) && r.max >= r.min)) &&
      lotSize >= r.min && (r.max === null || lotSize <= r.max));
    if (matches.length !== 1 || typeof matches[0].code !== 'string') return null;
    const initialCode = matches[0].code;
    let code = initialCode;
    const visited = new Set();
    for (;;) {
      if (visited.has(code)) return null;
      visited.add(code);
      const p = config.plans[code];
      if (!p || typeof p !== 'object') return null;
      if (typeof p.use === 'string' && p.use) { code = p.use; continue; }
      if (!Number.isSafeInteger(p.sample) || p.sample < 1 || p.sample > lotSize ||
          !Number.isSafeInteger(p.ac) || p.ac < 0 || p.ac >= p.sample ||
          !Number.isSafeInteger(p.re) || p.re !== p.ac + 1) return null;
      return { code: initialCode, planCode: code, sample: p.sample, ac: p.ac, re: p.re,
        level: config.level, aql: config.aql, method: config.method,
        source: config.source, version: config.version };
    }
  }
  return { resolve };
});
