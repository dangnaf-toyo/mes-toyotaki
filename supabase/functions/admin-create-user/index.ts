// Edge Function: admin-create-user
// Cho phép người dùng đã có vai trò 'admin' (bảng public.user_roles) tạo tài
// khoản Supabase Auth mới + gán vai trò ngay — thay việc phải vào Supabase
// Dashboard thủ công. Dùng service_role key (chỉ tồn tại phía server của
// Edge Function, không lộ ra trình duyệt) để gọi Auth Admin API.
//
// Deploy: supabase functions deploy admin-create-user
// Gọi từ trang tĩnh: POST {SUPABASE_URL}/functions/v1/admin-create-user
//   headers: Authorization: Bearer <access_token của người đang đăng nhập>,
//            apikey: <anon key>
//   body: { email, password, full_name?, role }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ROLES = ['admin', 'truong_ca', 'ipqc', 'qc_manager', 'kho_nvl', 'ke_hoach'];

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

    const { data: callerRoleRow } = await admin
      .from('user_roles')
      .select('role')
      .eq('user_id', caller.id)
      .maybeSingle();

    if (!callerRoleRow || callerRoleRow.role !== 'admin') {
      return json({ error: 'Chỉ tài khoản có vai trò admin mới được tạo tài khoản mới' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const rawUsername = body.username ? String(body.username).trim().toLowerCase() : null;
    const rawEmail = body.email ? String(body.email).trim().toLowerCase() : null;
    const password = String(body.password || '');
    const fullName = body.full_name ? String(body.full_name).trim() : null;
    const role = String(body.role || '');

    // Công nhân không có email thật -> đăng nhập bằng mã nhân viên (username).
    // Supabase Auth vẫn bắt buộc có email nên sinh email nội bộ không ai dùng
    // để nhận thư (@mes.local) — người dùng chỉ cần biết username + mật khẩu.
    if (!rawUsername && !rawEmail) return json({ error: 'Cần mã nhân viên (username) hoặc email' }, 400);
    if (rawUsername && !/^[a-z0-9._-]{2,32}$/.test(rawUsername)) {
      return json({ error: 'Mã nhân viên chỉ gồm chữ/số/._- , độ dài 2-32 ký tự' }, 400);
    }
    const email = rawEmail || (rawUsername + '@mes.local');

    if (!password) return json({ error: 'Cần mật khẩu' }, 400);
    if (password.length < 6) return json({ error: 'Mật khẩu tối thiểu 6 ký tự' }, 400);
    if (!ROLES.includes(role)) return json({ error: 'Vai trò không hợp lệ: ' + role }, 400);

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createErr) return json({ error: createErr.message }, 400);

    const newUser = created.user;
    const { error: roleErr } = await admin.from('user_roles').insert({
      user_id: newUser.id,
      email,
      username: rawUsername,
      full_name: fullName,
      role,
      created_by: caller.id,
    });

    if (roleErr) {
      // Tạo Auth user thành công nhưng ghi vai trò lỗi — dọn lại để không để
      // sót tài khoản "mồ côi" (đăng nhập được nhưng chưa có vai trò nào).
      await admin.auth.admin.deleteUser(newUser.id);
      return json({ error: 'Tạo tài khoản OK nhưng gán vai trò lỗi: ' + roleErr.message }, 500);
    }

    return json({ ok: true, user_id: newUser.id, email, username: rawUsername, role });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
