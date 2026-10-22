# QC staging review — 09/10/2026 (GMT+7)

Base: staging 6cca6ebefdfcece2aea55e7d1ad29676eda17b70. Isolated branch fix/qc-checks-history-staging-20261009. Original conflicted checkout preserved. No master/production changes.

## Behavior and affected files

- ipqc.html: retain all ten original checklist items and PDF reference behavior; separate dimension, appearance and one-line machine result. Store actual machine result in existing checklist JSON. Shared evidence list accepts ten photos. Existing warning-only save, OK/NG validations, queue and history remain.
- qc-manager.html: actual machine PASS/NG badges (green/red); legacy checkbox-only records remain unknown. Actual inspection timestamp displayed in GMT+7.
- iqc.html: actual received_at, separate sampled_at, start pickup_at and completed_at; datetime-local converted explicitly from GMT+7, never from browser timezone. No created_at fallback. Defect creation timestamp labeled Ngày nhập lỗi. Existing confirmation, completion, AQL, statistics, editing and image functions retained.
- oqc-daily.html: explicit actual inspection time and optional user-entered LOT/Task. Customer/model/date filtering and model drilldown added; existing edit, export, personnel selection and standards remain.
- shared/mes-qc-fields.js (new): explicit business timestamps, actual machine result and catalog-code-based defect names; custom/retired defect names preserved.
- shared/mes-oqc-history.js (new): complete paginated inspections; inclusive dates; one/multiple model and customer filters; inspection counts, quantities and weighted rates; per-model/per-defect summaries. New records snapshot current authoritative customer. Historical records lacking snapshot label customer as current directory, never silently backfill.
- shared/mes-oqc-record.js: canonical catalog names in read-only modal and Excel; actual time/customer/LOT/Task/result added. Legacy defect photos/metadata/duplicates remain.
- ncp-detail.html and shared/qc02-ncp.js: catalog-code-based names for structured defects and GMT+7 timestamps. Free-text NCP descriptions remain verbatim because their defect code/source is unknown; no guessed replacements. Catalog read failure retains saved content.
- scripts/build-mes-review.cjs: include the two new helpers in frontend-only build.
- supabase/migration_phase_T73_qc_checks_history_staging.sql (new): required STAGING ONLY migration. Add nullable event/source fields with no historical backfill. Narrow patch live IPQC validator 6→10; unknown validator aborts transaction. Rename only authorized vat_c Vật C→Vát C. New authenticated OQC wrapper preserves old RPC and immutable audit; changes atomically capture metadata audit.
- tests/mes-update.cjs: 28 regression checks against mocked APIs/storage.
- tests/qc-requirements.cjs (new): ten requested cases plus pagination beyond 1,000 records.
- tests/qc-migration.cjs (new): eight real local PostgreSQL/WASM checks, including repeatability, preservation, limits, authentication, audit and full transaction abort.
- QC_CHECKS_HISTORY_REVIEW.md: this report.

## Validation

47 checks passed (28 regression + 11 requirement/pagination + 8 local PostgreSQL). All 61 frontend scripts parse. Frontend build contains 52 assets, no SQL or dependencies. Test output has no application console errors. Browser behavior tests use jsdom and mocked API/storage; PostgreSQL tests run locally, not on Supabase. Actual authenticated staging uploads/production operations require user acceptance testing after deployment.

## Deployment prerequisite

At the last read-only check, staging jcjbleugnclzsghfpmvk did not have sampled_at, inspection_time or aliases and vat_c still read Vật C. User will execute T73 in staging SQL Editor. Do not deploy new frontend until migration succeeds and is verified. No live database writes were made by this coding session. Production project fgghikpzcxjqzahfiiil and shared connection/auth routing remain unchanged.
