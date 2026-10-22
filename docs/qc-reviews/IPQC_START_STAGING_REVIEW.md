# STAGING IPQC — Locked Start diagnosis and server-confirmed sessions

Date: 20/10/2026 (Asia/Bangkok). Base: staging a5e2aefa8989b40143355ace535514886fcfe5c0. Deploy title: **STAGING IPQC — Hiển thị lỗi T118 và xác minh phiên trước khi bắt đầu**.

## Confirmed cause

The live `/ipqc` page already loads the T118 session module. A failed `duc_ipqc_session(..., false)` disables Start; previously its error was placed in the timer output and overwritten by the 500 ms timer tick. Staging read-only API probes returned 42703 (missing `duc_ipqc_checkpoint.session_started_at`) and PGRST205 (missing session table in schema cache). T118 is not ready. CLI project list is empty and the explicitly targeted staging database query fails with HTTP 403 at `Initialising login role`.

Staging database: `jcjbleugnclzsghfpmvk`. Production database: `fgghikpzcxjqzahfiiil`. No production request, migration, permission change or business-record write was made. No SQL was changed or executed in this fix.

## Files and behavior

- `shared/mes-ipqc-session.js`: persistent accessible status and a separate read/retry button. Distinguish missing T118/schema cache, expired login, denied RLS, network errors and invalid session response. Start and inspection controls stay locked until the appropriate server response is verified. Timer starts only after the start RPC returns a valid saved session matching the checkpoint/user/machine/product/job. Lost start responses can recover by reading the same server session, without creating a second one. Submission timestamps and recovery responses are validated. Stale requests cannot change the newly selected checkpoint's controls. Existing checklist, photos and local draft behavior retained.
- `ipqc.html`: versioned session script URL to avoid stale cache.
- `tests/qc-session-ui.cjs`: retain 8 existing groups and add 8 failure/recovery groups (multiple individual cases per group).
- `tests/qc-session-browser.cjs`: real Chromium verifies persistent missing-backend message, locked Start, retry, server-confirmed start, unchanged start after choices/reload, native photo draft, and stopped timer on completion. Backend is mocked; this is not a live database smoke test.
- `IPQC_START_STAGING_REVIEW.md`: this report.

## Verification and rollout

Passed: 16 UI groups, 48 existing regressions, 3 Chromium scenarios; frontend parsing and build checked. No database test records created. Latest colleague changes T119 and D73 were preserved by fast-forwarding from staging before editing.

This deployment fixes diagnosis/recovery on the frontend already published with T118 dependencies. It does not make an unavailable backend operational. Actual Start/save/reload/complete testing on staging remains blocked until a project-authorized account applies `supabase/migration_phase_T118_qc_sessions_sources_ng.sql` on staging. Then use **Kiểm tra lại phiên**, Start, record evidence, reload, and submit; compare server start/end timestamps and ensure original NG remains NG. If migration/API/RLS is still unavailable, the UI must keep Start/results locked and show the exact API reason.

Deployment target only: Worker `mes-toyotaki`, account `8f888124185023ee553ef0d51c935f62`, https://mes-toyotaki.dangnaf.workers.dev/ipqc . GitHub master/Pages and production database are untouched.
