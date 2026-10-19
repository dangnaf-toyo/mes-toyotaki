# Staging QC T118 — 19/10/2026 (GMT+7)

Planned deploy title: **STAGING QC T118 — Zoom ảnh, phiên kiểm từng máy, nguồn NCP và duyệt tiếp tục SX từ NG**.

Base: staging 0bedce5d5c5a14b955c655dbcef5f3e56d09e73f. Isolated branch fix/qc-sessions-ncp-ng-staging-20261019. Original conflicted checkout and prior worktrees preserved. No production/master edits. Earlier IQC-role commit cc8fcbd is separate and not included in this scope.

## Behavior and files

1. shared/qc02-view.js — common photo dialog centered near fullscreen; zoom in/out, original pixel size, fit screen, wheel zoom anchored to pointer, bounded drag, pointer/two-finger pinch, keyboard and existing gallery navigation. PDF and hover preview remain. Native dialog close removes listeners.
2. ipqc.html — stop auto-start on open. Keep original checklist, standards, photos, OK/NG/warning validation and queue logic. Capture validated Submit click on server before photo upload and save via session-aware wrapper. Versioned viewer URL prevents stale cached viewer on QC pages.
3. shared/mes-ipqc-session.js (new) — explicit Start button, server start/submit timestamps and continuous elapsed clock independent of periodic lateness. Session is keyed to exact checkpoint/machine/model/job and account. IndexedDB saves actual photo Blobs, answers and notes; account-scoped pointer reopens active session after reload. Reopening does not reset time. Failed upload continues same session; lost save response checks authoritative result and avoids duplicate save. Clearing browser storage loses local draft contents, while server start persists.
4. qc-manager.html — retain existing duration column and delay calculation; display actual session duration plus start/end detail, including valid zero-second durations. Add independent NG decision state to completed real-time/history rows. Existing old duration values are not recalculated.
5. shared/mes-ncp-source.js (new) — manual sources Machine/IPQC, Department/process, Customer. Product code/name linked from master_products; customer suggestions from existing product customer fields; responsible staff from central account RPC. Non-machine sources hide machine/mold and send neither. Department/customer source, image uploads, quantities and location recorded; submit retry uses stable request UUID and cached uploaded URLs. Existing NG-linked NCP opening, sorting, repair, scrap, approvals and close flow stay in their original RPCs. Add source/department filters and source columns to open/closed lists.
6. ncp-detail.html and shared/qc02-ncp.js — source/department/customer visible in primary record and printable detail; source images join existing evidence gallery and use shared zoom. Unknown old source remains unrecorded; historical data is not backfilled.
7. shared/mes-ng-status.js (new) — offer explicit Forward NG after successful NG save; existing warning-only flow stays. Forward is idempotent on server. Original checkpoint/model/inspector/time/failed items/photos populate decision detail. Actual inspection NG is separate from pending/approved/refused/expired continuation status. Show responsible downstream process, approver, timestamp, scope and limit; click opens original check and decision details. Poll/realtime rereads authoritative data.
8. ipqc-approval.html — linked source detail button and NG-only approval form requiring reason, scope, next process, responsibility and time/quantity limit. Existing four-step role checks/override/rejection remain; decisions use the existing permission-enforcing RPC inside a versioned NG wrapper.
9. supabase/migration_phase_T118_qc_sessions_sources_ng.sql (new) — additive nullable metadata and new session table/RLS/RPCs. Start only on explicit action; owner-bound session and server-computed duration. Existing submit RPC body stays byte-for-byte unchanged; wrapper preserves its validations/side effects. Legacy history gets no new start/end values. NCP source wrapper calls original open RPC, retaining workflow and permissions. Exact NG checkpoint row lock serializes forwards; older creation clients also receive link/duplicate validation. NG handling conditions required on every approval step; old decision entry point cannot bypass them. A completed NG cannot become OK; continuation approval cannot automatically close a linked NCP. No old account/production/LOT/NCP data is rewritten by migration.
10. tests/mes-update.cjs, tests/qc-requirements.cjs, tests/qc-ui-followup.cjs — adapt existing 48 regressions to explicit Start/session RPC and new authorized SQL/viewer scope.
11. tests/qc-session-postgres.cjs (new) — 9 local PostgreSQL groups using original submit, NCP-open and role-enforcing approval functions: migration repeatability, preserved original RPC/legacy duration, owner/clock safety, independent NCPs, exact/idempotent NG forward, mandatory approval fields/roles and linked NCP preservation, anonymous/direct-write denial.
12. tests/qc-session-ui.cjs (new) — 8 mocked UI groups covering explicit start, draft reopen with selected-state display and photos, completion/NG offer, non-machine forms, statuses/details, upload failure, lost response, duplicate click and expiry label.
13. tests/qc-photo-browser.cjs (new) — real headless Chrome desktop mouse/wheel/pan and Chromium mobile two-finger touch/pinch; screenshots in .review.
14. tests/qc-session-browser.cjs (new) — real headless Chrome reload test using native IndexedDB and real photo Blob; API is mocked locally. Start time, answer styling, note and photo bytes survive reload. No page errors.
15. QC_T118_STAGING_REVIEW.md — this report.

## Verification

68 case/groups passed: 48 existing regressions + 9 PostgreSQL groups + 8 new UI groups + 3 browser scenarios. All frontend scripts parse. Browser photo tests exercise actual Chromium events (desktop and emulated mobile), not a physical iPhone/Android device. UI/API/storage services are mocked except real local PostgreSQL and native browser IndexedDB. No live staging accounts, inspection checkpoints or NCP records were created/modified during tests.

## Staging rollout prerequisite

GitHub reports write access. Supabase CLI projects list is still empty. Read-only staging GETs confirm session_started_at/session_completed_at and NCP source_type are absent. Therefore no Cloudflare frontend deploy yet.

1. Open SQL Editor of **jcjbleugnclzsghfpmvk** and execute the full T118 transaction. Keep existing functions/grants/security settings. Stop if migration fails.
2. Verify added schema, RPC execution permissions and live function compatibility. This migration does not require an Edge Function deploy. It does not include/run T108 or alter IQC roles.
3. Build frontend assets and deploy only Worker mes-toyotaki at https://mes-toyotaki.dangnaf.workers.dev/. Keep production GitHub Pages and Supabase fgghikpzcxjqzahfiiil untouched. Record deployment ID/title and commit on GitHub after actual deploy.
4. With authorized staging accounts, smoke test: Start -> answer/photo -> reload -> complete; compare server elapsed to submit time (upload latency excluded). Confirm waiting/periodic delay is separate and old history unchanged.
5. Create Gia công and Customer NCPs with no casting machine/mold; verify source filters/detail/photos/old disposition flow.
6. Send NG -> explicitly Forward -> open original evidence -> approve with reason/scope/limit/downstream responsibility -> check real-time/history status. Confirm inspection stays NG and linked NCP stays open. Verify denied role, repeated clicks, rejection and expiry.

Live authenticated smoke tests and actual deployment are pending migration/project access; local test success does not claim they passed. An active browser draft is local to that browser/device; its start time is stored on server and can be resumed by the same account. An in-progress session does not automatically transfer ownership to another account.
