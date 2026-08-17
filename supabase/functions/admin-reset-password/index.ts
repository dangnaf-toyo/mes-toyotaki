// Edge Function: admin-reset-password
// Cho phép người dùng đã có vai trò 'admin' (bảng public.user_roles) đặt lại
// mật khẩu cho BẤT KỲ tài khoản nào — dùng khi nhân viên quên mật khẩu (đa số
// tài khoản đăng nhập bằng mã nhân viên, email nội bộ @mes.local, không có
// hộp thư thật để tự "Quên mật khẩu" qua email như flow chuẩn của Supabase).
// Cùng pattern xác thực với admin-create-user (JWT của người gọi + tra
// user_roles.role = 'admin'), dùng service_role key chỉ tồn tại phía server.
//
// Deploy: supabase functions deploy admin-reset-password
// Gọi từ trang tĩnh: POST {SUPABASE_URL}/functions/v1/admin-reset-password
//   headers: Authorization: Bearer <access_token của người đang đăng nhập>,
//            apikey: <anon key>
//   body: { user_id, new_password }

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

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerData, error: callerErr } = await callerClient.auth.getUser(jwt);
    if (callerErr || !callerData?.user) return json({ error: 'Token không hợp lệ' }, 401);
    const caller = callerData.user;

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: callerRoleRow } = await admin
      .from('user_roles')
      .select('role')
      .eq('user_id', caller.id)
      .maybeSingle();

    if (!callerRoleRow || callerRoleRow.role !== 'admin') {
      return json({ error: 'Chỉ tài khoản có vai trò admin mới được đặt lại mật khẩu cho người khác' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const targetUserId = String(body.user_id || '').trim();
    const newPassword = String(body.new_password || '');

    if (!targetUserId) return json({ error: 'Thiếu user_id' }, 400);
    if (!newPassword || newPassword.length < 6) return json({ error: 'Mật khẩu mới tối thiểu 6 ký tự' }, 400);

    const { error: updErr } = await admin.auth.admin.updateUserById(targetUserId, { password: newPassword });
    if (updErr) return json({ error: updErr.message }, 400);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
