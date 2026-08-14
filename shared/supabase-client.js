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
};
