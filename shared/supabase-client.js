/**
 * ============================================================================
 * supabase-client.js — Khởi tạo Supabase client dùng chung cho mọi trang tĩnh
 * (Giai đoạn "bỏ Google" — thay Apps Script làm giao diện).
 *
 * Cách dùng: nhúng supabase-js từ CDN TRƯỚC file này, rồi nhúng file này:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
 *   <script src="../shared/supabase-client.js"></script>
 *
 * Sau đó dùng biến toàn cục `sb` (client) và các hàm `MesAuth.*` bên dưới.
 * ============================================================================
 */

const SUPABASE_URL = 'https://fgghikpzcxjqzahfiiil.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_WWugFHNNGGQPWZRsMxGyVA_YpsL4v3v';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const MesAuth = {
  /** Trả về session hiện tại (null nếu chưa đăng nhập). */
  async getSession() {
    const { data } = await sb.auth.getSession();
    return data.session;
  },

  /**
   * Bắt buộc đăng nhập mới cho xem trang — gọi ở đầu mỗi trang cần ghi dữ liệu.
   * Nếu chưa đăng nhập, chuyển hướng sang trang login (giữ nguyên URL hiện tại
   * để quay lại sau khi đăng nhập xong).
   * @returns {Promise<object>} session — chỉ resolve khi đã đăng nhập.
   */
  async requireAuth() {
    const session = await this.getSession();
    if (!session) {
      const returnTo = encodeURIComponent(window.location.href);
      window.location.href = 'shared/login.html?returnTo=' + returnTo;
      return new Promise(() => {}); // treo lại, trang đang chuyển hướng
    }
    return session;
  },

  async signOut() {
    await sb.auth.signOut();
    window.location.href = 'shared/login.html';
  },

  /** Tên hiển thị của user hiện tại (email, hoặc rỗng nếu chưa đăng nhập). */
  async getCurrentUserEmail() {
    const session = await this.getSession();
    return session ? session.user.email : null;
  },

  /**
   * "Mã NV_Tên NV" của user hiện tại — dùng ở MỌI nơi hiển thị/ghi "ai đã
   * thao tác" (last_updated_by, người kiểm IPQC, người duyệt KHSX...) THAY
   * VÌ email — tài khoản công nhân đăng nhập bằng mã NV có email nội bộ tự
   * sinh dạng nvXXX@mes.local, không có ý nghĩa để hiển thị. Trả về null
   * nếu chưa đăng nhập; fallback về username/full_name riêng lẻ hoặc email
   * nếu tài khoản chưa khai đủ 2 trường. Cache theo user_id trong phiên
   * trang để khỏi query lại mỗi lần gọi.
   */
  async getCurrentUserIdentity() {
    const session = await this.getSession();
    if (!session) return null;
    if (this._identityCache && this._identityCache.userId === session.user.id) return this._identityCache.text;
    const { data } = await sb.from('user_roles').select('username,full_name,email').eq('user_id', session.user.id).maybeSingle();
    const username = data && data.username ? data.username.trim() : '';
    const fullName = data && data.full_name ? data.full_name.trim() : '';
    const text = (username && fullName) ? (username + '_' + fullName)
      : (username || fullName || (data && data.email) || session.user.email);
    this._identityCache = { userId: session.user.id, text };
    return text;
  },

  /**
   * Tự đổi mật khẩu của tài khoản đang đăng nhập — xác minh mật khẩu cũ bằng
   * cách đăng nhập lại (Supabase không có API kiểm mật khẩu riêng), rồi cập
   * nhật mật khẩu mới. Ném lỗi (throw) nếu mật khẩu cũ sai hoặc mật khẩu mới
   * không hợp lệ — gọi nơi dùng tự bắt try/catch để hiện thông báo.
   */
  async changePassword(oldPassword, newPassword) {
    const session = await this.getSession();
    if (!session) throw new Error('Chưa đăng nhập');
    const { error: verifyErr } = await sb.auth.signInWithPassword({ email: session.user.email, password: oldPassword });
    if (verifyErr) throw new Error('Mật khẩu hiện tại không đúng');
    const { error: updErr } = await sb.auth.updateUser({ password: newPassword });
    if (updErr) throw new Error(updErr.message);
  },
};
