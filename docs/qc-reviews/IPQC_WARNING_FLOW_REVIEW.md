# IPQC warning flow correction — 09/10/2026

Base: current GitHub staging c9fe0aaf571cdb6607e07cf6b1941faf64848527. Includes e33b3e7 and c9fe0aa packaging/tag updates. Master c9a1ee21f7f75f8805bdad009b8beb4d310af4ff is not modified. Isolated branch: fix/ipqc-warning-only-staging-20261009. Original conflicted checkout and previous worktrees are untouched.

## Behavior implemented without database changes

- IPQC presses CẢNH BÁO once from its existing valid inspection. No warning-save button, continuation request form, production reason, hours, quantity or countermeasure is requested from IPQC.
- Existing duc_submit_ipqc_check saves CANH_BAO in duc_ipqc_checkpoint with the existing inspection checklist, note, photo URLs, inspector and inspection timestamp. No continuation request RPC is called from IPQC.
- Existing evidence/checklist/note validation remains. A double click does not save twice. If a save response is lost, the saved checkpoint is checked automatically; there is no second save step. A checkpoint saved with another result is never overwritten by this flow.
- Approval page lists saved CANH_BAO checkpoints that have no linked continuation request. Label: CÓ CẢNH BÁO - CHƯA CÓ ĐỀ NGHỊ TIẾP TỤC SX. This is a derived warning state, not a fake request or an invented database status.
- Warning details show machine/model/process, failed checklist items, note, photos, inspector and actual inspection timestamp. Existing real id_dong identifies the production row; Task/tem/LOT is shown only if a verified field exists on that row. No latest tag from machine/model is guessed.
- Realtime client broadcast requests an immediate reread; payload contains only refresh:true. Database-change listeners and 15-second polling also reread authoritative data. No publication, RLS or database configuration is changed. Actual live delivery remains to be verified between two authenticated staging accounts.
- Sản xuất opens the exact warning and chooses ĐỀ NGHỊ TIẾP TỤC SẢN XUẤT. The form binds the checkpoint/job, shows original evidence, and collects production reason, temporary countermeasure, time/hour/quantity limit, authenticated requester, department and optional note. A stale warning cannot be reassigned to another model/job.
- The production request uses the existing RPC only after Sản xuất submits. Department/countermeasure/note are retained in existing reason text and creation audit JSON, without adding columns. Original warning/checklist/photos remain unchanged.
- Existing four-step approval, rejection, audit and permission checks are preserved. Đồng ý still executes the original Duyệt decision.

## Changed files

1. ipqc.html — remove production dialog; one-click warning button and accurate confirmation.
2. shared/mes-ipqc-warning.js — warning-only save, click guard, save-response recovery and realtime refresh event.
3. shared/mes-ipqc-flow.js — warning inbox reads, real checkpoint association and existing production-role UI controls.
4. ipqc-approval.html — warning inbox, read-only warning detail, hidden production proposal form and proposal-only fields. Obsolete submit handler removed.
5. shared/mes-ipqc-approval.js — warning display/realtime reread and bound production proposal submission.
6. tests/mes-update.cjs — warning-only, response-loss, exact-link, role, evidence and realtime regression tests, plus previous OQC preservation checks.
7. This report.

No OQC/IQC/QC Manager/NCP/BOM/material/tag/packaging function is edited. No SQL file, database connection routing or shared authorization helper is edited. No live database write test is run.

## Verification

28 offline tests passed with all API/storage calls mocked. Frontend build contains 50 assets and zero SQL files; SHA-256 verified, 60 scripts parsed and zero missing local script dependencies. All 50 live staging assets matched the current staging base before publishing. Tests include original OK/NG/photo/checklist preservation, no request from one warning click, automatic response-loss confirmation, production proposal for the exact warning, no cross-model reassignment, realtime reread and existing OQC edit/history/export regression cases.

## Remaining backend requirements — not implemented or claimed complete

- YÊU CẦU BỔ SUNG: repository backend currently accepts Duyệt, Từ chối and Phê duyệt trực tiếp. The approval table decision constraint and D61 RPC do not implement supplementation/resubmission. A UI-only button would be misleading and would bypass the authoritative workflow; none was added.
- Durable notifications to the approver: T66 create RPC only inserts notifications for EARLY_WARNING, not every normal production proposal. Frontend refresh events are not durable account notifications. This requirement needs a reviewed staging backend change.
- Production-only request creation is controlled in the UI using existing role identifiers; T66 server creation RPC still permits any authenticated user. Server-enforced separation would require a backend change; frontend restrictions are not claimed as server security.
- Cross-device atomic request duplication prevention and live RPC/RLS/realtime behavior remain unverified. No schema or stored data is changed to address these limits.

The user's standing prohibition on database changes prevents silently implementing these backend changes. Any such change must first be approved for staging only. This correction does not constitute completion of those three backend requirements.

Realtime API usage checked against [Supabase Broadcast documentation](https://supabase.com/docs/guides/realtime/broadcast).
