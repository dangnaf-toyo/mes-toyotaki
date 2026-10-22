# QC UI follow-up — 10/10/2026 (GMT+7)

Base staging: 91960f8aab9bae3d6ef9962621f18abfc72640dc. Isolated worktree; original conflicted checkout preserved. Scope is the follow-up UI request. No SQL migration or database connection/auth routing is edited by this follow-up.

## Files / resulting behavior

1. ipqc.html — three sibling sections; machine heading and exactly one literal black plain row “Toàn bộ chữ màu đen” with Đạt/Không đạt. Existing ten dimension/appearance items and saved machine boolean remain.
2. oqc-daily.html — remove manual time input and its validation/payload; one model search/chip control; searchable central inspector selector. Customer/date/shift filters and existing save/edit/export preserved.
3. shared/mes-oqc-history.js — model code/name suggestions from master_products, validated catalog selections, multiple chips/removal/clear and model drilldown. Exact inspector code filtering from existing employee/account directory. Customer suffix removed. Existing inspection_time is never overwritten by this form. No creation-time fallback is introduced.
4. ipqc-approval.html — separate warning fault/photo columns; responsive uniform thumbnail grid; dedicated sections in detail. Request display hides QC02 markers. Audit display uses readable labels and retains detail values.
5. shared/mes-ipqc-approval.js — separate machine/fault/photo/inspector groups, actual PASS/NG display, no invented PASS from old checkbox markers. Existing exact job/checkpoint association, proposal form, upload URLs, zoom, permissions, decisions and realtime refresh remain. Original warning content is retained in proposal payload; only its UI copy is cleaned.
6. shared/mes-qc-fields.js — display-only QC02 marker removal; no saved data is rewritten.
7. qc-manager.html — clean internal markers from displayed notes.
8. ncp-detail.html — clean internal markers from displayed free-text description, without changing saved text.
9. shared/qc02-ncp.js — clean markers in read-only field output; preserve values/data.
10. tests/mes-update.cjs — adapt mocks to time-field removal and metadata preservation; existing 28 behavior checks remain.
11. tests/qc-requirements.cjs — adapt existing model tests to validated selection API; existing 11 checks remain.
12. tests/qc-ui-followup.cjs (new) — nine requested follow-up cases, including literal machine row, suggestions/chips, employee selection, no manual time/payload, stored-time preservation, photo zoom, clean notes and immutable raw warnings.
13. QC_UI_FOLLOWUP_REVIEW.md — this report.

## Validation and limits

48 browser behavior checks (28 regression + 11 prior requirements + 9 follow-up cases), using jsdom with mocked APIs/storage. No application errors in test console output. All 61 scripts parse; frontend-only build has 52 assets and no SQL/dependencies. Eight previously passed local PostgreSQL migration checks remain applicable; this follow-up does not change T73.

Actual browser layout and authenticated live storage/production workflow need staging acceptance testing after deployment. No live write tests performed.

## Deployment prerequisites

Read-only staging checks on 10/10/2026 still report missing iqc_lots.sampled_at, oqc_daily_inspection.inspection_time and quality_defect_catalog.aliases. User agreed to execute T73 in the SQL Editor of jcjbleugnclzsghfpmvk. Do not deploy the combined frontend before successful migration verification. Production fgghikpzcxjqzahfiiil is untouched.

Manual OQC time input is removed as requested. Existing explicit inspection_time stays visible and preserved. No existing automatic actual-inspection-time source was found; new records remain unknown until the user identifies the actual event/source. Do not use created_at/updated_at or current save time as invented inspection time.
