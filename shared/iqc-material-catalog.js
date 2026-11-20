/* One BOM/inventory material identity, alongside the unchanged product master. */
const IqcMaterialCatalog = (() => {
  let request = null, generation = 0,
    current = { products: [], materials: [], available: false };
  const display = (item) => item.kind === "nvl" ? "[NVL] " + item.code :
    (resolve(item.code) ? item.code : "[SP] " + item.code);
  async function load(force = false) {
    if (request && !force) return request;
    const turn = ++generation;
    const next = (async () => {
      const { data, error } = await sb.rpc("iqc_nvl_danh_muc");
      if (error || !data || !Array.isArray(data.san_pham) || !Array.isArray(data.nvl)) {
        throw error || Error("Không tải được danh mục sản phẩm và NVL.");
      } else {
        const unique = (rows, kind) => [
          ...new Map((rows || []).filter((r) => r.code).map((r) => [r.code, { ...r, kind }])).values(),
        ];
        const updated = { products: unique(data.san_pham, "san_pham"), materials: unique(data.nvl, "nvl"), available: true };
        if (turn === generation) current = updated;
      }
      return current;
    })();
    request = next;
    try {
      const result = await next;
      return request !== next ? await request : result;
    } catch (e) {
      if (request === next) request = null;
      throw e;
    }
  }
  function resolve(value, kind) {
    const text = String(value || "").trim();
    const materialOnly = kind === "nvl" || /^\[NVL\]\s*/i.test(text);
    const productOnly = kind === "san_pham" || /^\[SP\]\s*/i.test(text);
    const code = text.replace(/^\[(?:NVL|SP)\]\s*/i, "").toLocaleLowerCase("vi");
    if (!code) return null;
    const candidates = materialOnly ? current.materials : productOnly ? current.products : [...current.products, ...current.materials];
    const explicit = /^\[(?:NVL|SP)\]\s*/i.test(text);
    const raw = text.replace(/^\[(?:NVL|SP)\]\s*/i, "");
    if (explicit) {
      const exact = candidates.filter((r) => r.code === raw);
      if (exact.length === 1) return exact[0];
    }
    const matches = candidates.filter((r) => (explicit ? [r.code] : [r.code, r.supplierCode]).some((v) => v && String(v).trim().toLocaleLowerCase("vi") === code));
    return matches.length === 1 ? matches[0] : null;
  }
  function options(list) {
    list.replaceChildren(
      ...[...current.products, ...current.materials].map(
        (r) =>
          new Option(
            (r.kind === "nvl" ? "NVL" : "Sản phẩm") +
              " · " +
              r.code +
              " — " +
              r.name +
              (r.supplierCode ? " · NCC: " + r.supplierCode : "") +
              (r.grade ? " · " + r.grade : ""),
            display(r),
          ),
      ),
    );
  }
  return {
    load,
    resolve,
    options,
    display,
    get current() {
      return current;
    },
  };
})();
