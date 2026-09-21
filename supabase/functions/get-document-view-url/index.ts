// Edge Function: get-document-view-url
// Trả về signed URL ngắn hạn (300 giây) để XEM bản view-only (PDF/ảnh) của 1
// phiên bản tài liệu kỹ thuật, sau khi tự kiểm tra quyền 'read' của người gọi
// qua RPC has_doc_permission (bucket 'tech-documents' là PRIVATE, client
// không được gọi thẳng storage.from()). Mọi lượt xem/lượt bị chặn đều được
// ghi vào document_access_log để phục vụ audit (không cho tải bản xem).
//
// Deploy: supabase functions deploy get-document-view-url
// Gọi từ trang tĩnh: POST {SUPABASE_URL}/functions/v1/get-document-view-url
//   headers: Authorization: Bearer <access_token của người đang đăng nhập>,
//            apikey: <anon key>
//   body: { version_id }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method không hỗ trợ' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '');
    if (!jwt) return json({ error: 'Thiếu Authorization header (chưa đăng nhập?)' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Xác định người gọi qua JWT của chính họ (không tự khai báo user_id).
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerData, error: callerErr } = await callerClient.auth.getUser(jwt);
    if (callerErr || !callerData?.user) return json({ error: 'Token không hợp lệ' }, 401);
    const caller = callerData.user;

    const admin = createClient(supabaseUrl, serviceKey);

    const body = await req.json().catch(() => ({}));
    const versionId = String(body.version_id || '').trim();
    if (!versionId) return json({ error: 'Thiếu version_id' }, 400);

    const { data: versionRow, error: versionErr } = await admin
      .from('document_versions')
      .select('id, document_id, file_path_view')
      .eq('id', versionId)
      .maybeSingle();
    if (versionErr || !versionRow) return json({ error: 'Không tìm thấy phiên bản tài liệu' }, 404);

    const { data: docRow, error: docErr } = await admin
      .from('documents')
      .select('id, category_id')
      .eq('id', versionRow.document_id)
      .maybeSingle();
    if (docErr || !docRow) return json({ error: 'Không tìm thấy tài liệu' }, 404);

    // Kiểm tra quyền qua callerClient (JWT của người gọi) để auth.uid() trong
    // RPC has_doc_permission là đúng người gọi, không phải service_role.
    const { data: allowed, error: permErr } = await callerClient.rpc('has_doc_permission', {
      p_category_id: docRow.category_id,
      p_quyen: 'read',
    });
    if (permErr) return json({ error: 'Lỗi kiểm tra quyền: ' + permErr.message }, 500);

    if (!allowed) {
      await admin.from('document_access_log').insert({
        document_version_id: versionId,
        user_id: caller.id,
        action: 'view_attempt_blocked',
      });
      return json({ error: 'Bạn không có quyền xem tài liệu này' }, 403);
    }

    const { data: signed, error: signErr } = await admin.storage
      .from('tech-documents')
      .createSignedUrl(versionRow.file_path_view, 300);
    if (signErr || !signed?.signedUrl) {
      return json({ error: 'Không tạo được đường dẫn xem: ' + (signErr?.message || '') }, 500);
    }

    const thoiGian = new Date().toISOString();
    await admin.from('document_access_log').insert({
      document_version_id: versionId,
      user_id: caller.id,
      action: 'view',
      thoi_gian: thoiGian,
    });

    return json({
      ok: true,
      url: signed.signedUrl,
      ten_nguoi_xem: caller.email,
      thoi_gian: thoiGian,
    });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
