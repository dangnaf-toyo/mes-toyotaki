/* One BOM/inventory material identity, alongside the unchanged product master. */
const IqcMaterialCatalog = (() => {
  let request = null,
    current = { products: [], materials: [], available: false };
  const display = (item) => (item.kind === "nvl" ? "[NVL] " + item.code : item.code);
  async function load(force = false) {
    if (request && !force) return request;
    const next = (async () => {
      const { data, error } = await sb.rpc("iqc_nvl_danh_muc");
      if (error || !data || !Array.isArray(data.san_pham) || !Array.isArray(data.nvl)) {
        const rows = await Qc02Data.readAll("master_products");
        current = {
          products: rows.map((r) => ({ kind: "san_pham", code: r.ma_sp, name: r.ten_sp || "" })),
          materials: [],
          available: false,
        };
      } else {
        const unique = (rows, kind) => [
          ...new Map((rows || []).filter((r) => r.code).map((r) => [r.code, { ...r, kind }])).values(),
        ];
        current = { products: unique(data.san_pham, "san_pham"), materials: unique(data.nvl, "nvl"), available: true };
      }
      return current;
    })();
    request = next;
    try {
      return await next;
    } catch (e) {
      if (request === next) request = null;
      throw e;
    }
  }
  function resolve(value, kind) {
    const text = String(value || "").trim(),
      isMaterial = kind === "nvl" || text.startsWith("[NVL] ");
    const code = text.replace(/^\[NVL\]\s*/, "");
    return (isMaterial ? current.materials : current.products).find((r) => r.code === code) || null;
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
