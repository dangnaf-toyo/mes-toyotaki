# Bổ sung định mức và capa kiểm tra OQC – hiệu suất kế hoạch 80%

Date: 20/10/2026 (Asia/Bangkok). Base: staging `f5f1dac128498c10d2e8f232e3465fef56331c8d`. Production/main/master and production connections are unchanged.

## Implemented

- New Quality menu **Định mức kiểm tra OQC**, route `/oqc-capacity`. Products come from existing `master_products`, with pagination. No new model/staff/routing catalog. Existing OQC inspector selection remains the central QC directory.
- Editable named inspection steps and positive decimal seconds/PCS. Server recomputes the total. Immutable, effective-dated versions include actual authenticated updater and timestamp; no editing/deleting saved versions.
- Fixed planning efficiency 80%. Hours/person are explicitly entered before the factor, never defaulted to 7. Capacity is floor(hours × 3600 × .8 / seconds). Invalid/missing norm or hours produces a reason, not a valid zero result.
- Daily full-inspection plans with quantity/model, shared daily hours, individual FTE/ceil headcount and summed workload/total FTE/ceil headcount. Weekly `cd_khsx_tuan_plan` OQC quantities are available only as explicit suggestions; they are not silently asserted to be full-inspection plans. Existing saved model plans keep their original standard version when edited. Daily revision detects concurrent/stale saves. Changes are audited.
- Explicit scopes on new daily OQC saves: FULL_POST_MACHINING, SAMPLING, OTHER or unknown. Scopes and per-result standard snapshots live in a sidecar referencing `oqc_daily_inspection`; the existing save RPC bodies are unchanged. Date/model mismatches caused by older clients are excluded instead of reusing the wrong norm.
- Old records remain unknown, visible in old OQC screens, excluded from full-inspection reconciliation. No old-data mass classification or norm backfill. If no effective standard exists at a new result's inspection date, its norm stays null even after later standards are added.
- Results use exact `inspection_date` and model and count OK + NG. Only explicit full-after-machining scope is included. Earned seconds use each result's saved version; missing snapshots make efficiency incomplete instead of summing a misleading partial total.
- Actual manpower allows multiple groups of people × actual hours. A plan suggestion is an unsaved draft until explicit confirmation. Efficiency uses earned seconds / (confirmed person-hours × 3600), with no additional .8 in the denominator. Completion and actual efficiency are separate. Completion totals cover planned models; unplanned full-inspection output is shown separately and contributes to actual efficiency. Labor entry applies only to this inspection scope, with a note to avoid double-counting shared staff-hours.

## Files

- `oqc-capacity.html`: standard, plan, actual labor and reconciliation page, mobile layout and history.
- `shared/oqc-capacity.js`: live reads, edit/retry/permission states, snapshot previews, suggestions and explicit saves.
- `shared/oqc-capacity-math.js`: common capacity/FTE/completion/efficiency formulas and missing-data states.
- `shared/mes-oqc-scope.js`: additive scope field, version detail, compatibility with legacy OQC saves if T120 is absent. Old records cannot be silently classified.
- `oqc-daily.html`: optional scoped save dispatch and script include; original validation and inspector/master sources retained.
- `shared/mes-oqc-record.js`: scope/version detail in the existing read-only record dialog.
- `shared/navbar.js`: only new Quality menu link and page title metadata.
- `supabase/migration_phase_T120_oqc_capacity_staging.sql`: six new tables with RLS/read grants, six public authenticated RPCs, private helpers, immutable version/audit triggers, effective-version index. Requires existing T67/T73 OQC; independent of T118. No old table/RPC/grant/body rewrite and no old-data DML on application.
- `tests/oqc-capacity-postgres.cjs`: 9 real local PostgreSQL/formula groups, including migration repeatability, unchanged old RPC/data, decimals, version snapshots, date/model/scope exclusions, legacy edits, 80% example, concurrent plan revision and RLS/permissions.
- `tests/oqc-capacity-ui.cjs`: 6 mocked UI groups for steps/capa, shared-day staffing, plan snapshots, explicit labor, missing backend/view permissions and incomplete data.
- `tests/oqc-capacity-browser.cjs`: 2 actual Chromium desktop/mobile scenarios (mock backend); screenshots under `.review`.
- `tests/qc-session-ui.cjs`: existing 16 groups plus 2 OQC scope/legacy-fallback groups.
- `tests/mes-update.cjs`: whitelist only T120 and the two new navbar lines while preserving unrelated-resource assertions.
- `OQC_CAPACITY_T120_STAGING_REVIEW.md`: this report.

## Validation

83 groups/checks passed: 9 SQL/formula + 6 new UI + 2 Chromium + 18 session/scope UI + 48 existing regressions. All frontend scripts parse; 68 frontend assets built, no SQL/dependencies in deployment. Browser mobile tests use emulation, not a physical phone. No live business records were created/edited by these tests.

## Staging backend prerequisite and deployment

Target only: `https://mes-toyotaki.dangnaf.workers.dev/oqc-capacity`, Worker `mes-toyotaki`, Cloudflare account `8f888124185023ee553ef0d51c935f62`. Supabase staging is `jcjbleugnclzsghfpmvk`; production is a separate project and is never targeted.

At inspection, CLI projects list is empty; a SELECT explicitly targeting staging still returns **403 at Initialising login role**. Therefore T120 has NOT been executed live. The page clearly reports missing backend and disables new writes; legacy unknown-scope OQC saves still use the existing RPC. Publishing this frontend is not evidence that live database persistence was tested.

An authorized project owner must execute the complete T120 transaction in the SQL Editor of staging **jcjbleugnclzsghfpmvk** only, or provide a CLI session with existing management/database rights for that project. No access-right changes are performed by this task. Stop on errors. Running T120 does not apply T118 or any other migration.

After SQL success, reload the page and verify `oqc_capacity_info()` returns version 120 under an authenticated MES account. Smoke test: save 10 + 8 + 12 second steps; 7h gives 672 PCS and 8h gives 768; two 500-PCS/30s model plans at 7h total 1.488095 FTE / 2 people; a new full-scope record with OK + NG = 672 and 1 × 7 actual hours gives 80% actual efficiency, and 100% completion if plan is 672. Check sampling/other/unknown records excluded. Add a new norm and confirm old plan/result values remain unchanged. Verify read-only role, legacy OQC save, detail, photos and export. Do not claim authenticated live smoke tests passed until these have actually run.
