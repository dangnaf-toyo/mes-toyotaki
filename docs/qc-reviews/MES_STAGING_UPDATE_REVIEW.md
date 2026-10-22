# MES staging review — 08/10/2026

## Source and preservation

- GitHub staging: `074c1cd90b52038b2bbc9826cd7fdf0b7bf42226`.
- GitHub master: `c48343ec3a5c4fef914e0761068b87e8f65b1ff5`.
- Work branch: `fix/mes-ipqc-oqc-staging-20261008`; worktree: `.mes-update-worktree`.
- Created from current staging. No old QC snapshot or cancelled IPQC draft was copied into this branch.
- Nine live staging assets matched staging `074c1cd`, ignoring CRLF/LF. Both GitHub branch heads were rechecked before commit.
- No push, merge, deployment, migration or live database write was performed.

The original checkout remains on `staging`, HEAD `1172142`, MERGE_HEAD `55601ab`. Its 15 changed/untracked files and Git index/merge metadata were copied to `.integration-backups/2026-10-08T07-59-54-460Z`. A final integrity check found zero changes to those saved files and identical index stages. The cancelled worktree was left alone.

Five original conflicts were examined and remain unresolved under the latest instruction prohibiting merge without confirmation:

| File | Functional difference |
| --- | --- |
| `ghi-nhan-tem-thanh-pham.html` | Preserve staging's production-day behavior rather than import the older incoming version. |
| `iqc.html` | Reference visibility and shared image-viewer version differ from current staging. |
| `ncp-detail.html` | Older layout/lightbox differs from the current compact layout/shared viewer. |
| `oqc-daily.html` | Older free-text employee entry/charts differ from the current OQC-only employee selector. |
| `quan-ly-danh-muc.html` | Staging-specific raw-material management must be retained. |

No bulk “accept current/incoming” operation or change to the conflicted index was made.

## Files and behavior

1. `ipqc.html`: Unchanged original checklist is independent of standard data. Loading/opening/closing a reference cannot replace answers. Cảnh báo opens the reason/scope form on the IPQC screen; sending saves the inspection then creates a linked continuation request.
2. `ipqc-approval.html`: Running-production search/selection, optional verified Task/LOT, exact warning selection, evidence preview, defect type/quantity and “Yêu cầu của tôi”.
3. `oqc-daily.html`: Actual `inspection_date`, multiple other-defect rows and read-only history popup; existing personnel/catalog controls retained.
4. `sanluong-supabase.html`: Only master's missing “KPI QLSX - Giao hàng” label was added. Master's deletions of staging BOM/material functionality were not imported.
5. `shared/mes-ipqc-flow.js`: Active production/checkpoint verification, original source metadata, existing request RPC, existing-request/audit-token checks and same-browser tab coordination. SQL remains the authority for approval permissions.
6. `shared/mes-ipqc-warning.js`: Same-screen submission and safe retry after the inspection has been saved.
7. `shared/mes-ipqc-approval.js`: MES-backed creation controls and UI permission checks matching existing four-step roles. No automatic production permit is granted.
8. `shared/mes-oqc-record.js`: Legacy/retired/duplicate defects and image metadata retained on edit; NG/%NG calculation; stored inspection date preserved; record/photo popup; safe Excel aggregation.
9. `tests/mes-update.cjs`: Offline behavior/regression tests, all APIs/storage mocked.
10. `scripts/build-mes-review.cjs`: Frontend-only local build; no deployment command.
11. This report.

IQC, OQC shipment inspection, QC Manager, NCP, BOM, material management, navbar, auth/database routing and existing shared QC helpers remain unchanged. No SQL file was edited. The one-time preparation script is left untracked and excluded from the commit.

## Validation

- 23 offline checks passed: standards/checklist isolation, PDF viewing, evidence/OK/NG validation, direct warning request creation, retry after a lost response, stale/paired production jobs, optional LOT/Task, ordinary-account approval restrictions, manager step roles, direct-request retry tokens, same-browser tab coordination, own-request filtering, multiple/removable other-defect rows, totals, legacy defect/image preservation, original inspection date on edit, read-only popup/photo viewing, missing date and Excel aggregation.
- Static build succeeded: 50 frontend assets, zero SQL files. Output: `.review/build-2026-10-08T09-16-04-184Z`.
- SHA-256 verification passed for all assets; 60 scripts parsed; zero missing local script dependencies.
- Original local files and conflict index stages verified unchanged.
- No authenticated live write/approval test was run. Live RLS/RPC enforcement and notifications require verification after staging deployment is authorized.

```powershell
$env:MES_JSDOM_PATH='path-to-an-existing-jsdom-installation'
node tests/mes-update.cjs
node scripts/build-mes-review.cjs
```

## Limits and pending work

- User chose actual OQC date only, inspection time pending verification. Source defines `inspection_date` as a date. Missing date/time is reported; `created_at`/`updated_at` are never substituted. No timestamp metadata or schema extension was introduced.
- Standard data is keyed by model; no authoritative process mapping was found. Model PDF viewing is retained with an explicit tooltip; an explicitly mismatched process, if returned, is not shown for IPQC. Correct mapping by process remains unverified pending its real source.
- No unambiguous Task/LOT-to-production-row relation was found. Verified source values are used if present; otherwise fields stay blank. Real `id_dong` and, for warnings, `id_checkpoint` identify the job/check. No recent tag is guessed from machine/product names.
- Evidence/source metadata uses the existing checkpoint link and creation audit JSON. Typed request columns, backend RPCs, states and notification logic are unchanged.
- Retry protection and same-browser tab coordination passed. Atomic duplicate prevention across different devices has not been verified in the live backend and is not claimed without a database-side guarantee.
- Original local conflict resolution, merge into staging, push and deployment require confirmation. No deploy number was reserved; the next number must be checked against current history at deployment time.
