# Gộp T118 + T120 – cập nhật staging

Release date: 20/10/2026 (Asia/Bangkok). Base: staging `dc46b58b0fc8a69a227ad144c42551c414826774`.

## Composition and conflict review

Both component commits are already ancestors of this staging release: T118 `6d857f4af33cb2a3a2e039e52e305a65fc3ed52b`, its IPQC Start/retry correction `f5f1dac128498c10d2e8f232e3465fef56331c8d`, and T120 `dc46b58b0fc8a69a227ad144c42551c414826774`. They are packaged as one deployment, without re-copying or cherry-picking modules. No Git conflict exists. Existing T116/T117/T119/D73 staging changes remain in the same history. No reset, force push, master/main replacement or production operation.

T118 retains shared image zoom/pan/pinch, explicit server-confirmed IPQC Start and elapsed time/draft restoration, persistent API/migration errors, independent NCP sources, and exact NG continuation approval with original NG and open NCP preserved. T120 retains versioned OQC step standards, daily planning and actual labor, explicit full-after-machining inspection scope, separate completion/efficiency metrics, and historical snapshots. Product/staff catalogs and image viewer are reused, not duplicated. Planning efficiency remains fixed at **80%**; work hours are user inputs before that factor. No fixed seven-hour default. Old unknown-scope OQC data remains visible but excluded from the new full-inspection report.

`scripts/check-qc-combined-release.cjs` verifies that the component migrations do not replace each other's function names and that the six integration pages include each shared script once. The frontend builder deduplicates paths and packages only HTML/shared assets. Existing `shared/supabase-client.js`, masters and production routing are unchanged.

## Combined verification

99 checks/groups passed on this exact combined code:

- 11 T118/combined PostgreSQL groups: original 9 plus both migrations applied/reapplied in one database, unchanged original RPCs and saved data, and concurrent availability of IPQC and OQC behavior.
- 9 OQC PostgreSQL/formula groups.
- 48 existing regressions for IPQC/IQC/OQC/approvals/history/photos/personnel.
- 18 session/scope UI groups.
- 6 OQC capacity UI groups.
- 7 actual Chromium scenarios: desktop image zoom/pan, mobile pinch, missing-backend IPQC recovery, native draft/photo reload, timer completion, OQC desktop and OQC mobile.

The shared-database test applies T118 and T120 together, rechecks original submit/approval/NCP/OQC RPC definitions byte-for-byte, and confirms old checkpoint results/duration and NCP/request records are unchanged. It then saves scoped OQC output of 672 PCS at 30 seconds, a 672-PCS plan and confirmed 1 × 7 actual hours: completion = 100%, actual efficiency = 80%. IPQC still starts/completes independently, the previous NG remains NG and its NCP remains open. A test fixture initially omitted mandatory IPQC evidence; it was corrected to use a valid photo/checklist, without relaxing product validation.

Also run the release audit and frontend parser/build. UI/browser APIs are mocked; PostgreSQL tests are real local databases. Mobile browser tests use emulation. These are not authenticated live staging smoke tests. No live business records or old-data backfill are used for testing.

## Backend status and staging-only rollout

Target: https://mes-toyotaki.dangnaf.workers.dev/ . Worker: `mes-toyotaki`, Cloudflare account `8f888124185023ee553ef0d51c935f62`. Supabase target: **jcjbleugnclzsghfpmvk** only. Production/main/master and production project configuration/data are not targeted.

The explicitly targeted Management API SELECT still returns **403 at Initialising login role**. Without that permission, this release does not execute migrations. Frontend deployment does not imply that database-backed features have been activated. Existing guards retain clear missing-backend diagnostics and disable unconfirmed writes; ordinary unscoped OQC saves retain their old RPC path.

Migration source is maintained once per task, not duplicated in a third combined SQL file:

1. `supabase/migration_phase_T118_qc_sessions_sources_ng.sql`.
2. `supabase/migration_phase_T120_oqc_capacity_staging.sql` (requires existing T67/T73 OQC, independent of T118).

Apply on staging only with a project-authorized account, stop on errors, then verify tables/functions/RLS and smoke-test actual saves before claiming full activation. Do not alter access rights or apply SQL on production. After SQL is available: image zoom/pinch; IPQC Start → answer/photo → reload → complete; department/customer NCP without casting machine/mold; NG forward/approval preserving NG and open NCP; OQC multi-step decimal standard/variable hours/multi-model aggregate staffing; exact date/model/full-scope OK+NG reconciliation; explicit labor confirmation; 80% actual efficiency versus 100% completion; historical standard snapshots and old OQC functions.

## Release-only changes

- `tests/qc-session-postgres.cjs`: optional combined integration suite hook via `MES_TEST_COMBINED_QC=1`.
- `tests/qc-combined-postgres.cjs`: two same-database compatibility/runtime groups.
- `scripts/check-qc-combined-release.cjs`: deduplication and final OQC rules audit.
- `QC_T118_T120_STAGING_RELEASE.md`: consolidated release report.

The deployed frontend is the full existing T118+T120 code, not a documentation-only site. This release does not rewrite working product code merely to manufacture a merge diff.
