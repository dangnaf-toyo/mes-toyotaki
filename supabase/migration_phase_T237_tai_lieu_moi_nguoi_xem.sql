-- T237 (10/11/2026): Tài liệu kỹ thuật — MỌI tài khoản đã đăng nhập được XEM mọi tài liệu
-- (mọi loại, mọi mã SP). Quyền ghi (tạo / sửa tên / tải phiên bản / duyệt / thu hồi) và
-- tải bản gốc CAD (download_source) GIỮ NGUYÊN như cũ.
-- Bản xem vẫn đi qua Edge Function get-document-view-url (watermark tên người xem),
-- hàm đó gọi has_doc_permission(..., 'read') nên tự hưởng thay đổi này.
-- Bảng document_permissions vẫn giữ (các dòng 'read' giờ không còn tác dụng).

create or replace function public.has_doc_permission(p_category_id uuid, p_quyen text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    when p_quyen = 'read' then auth.uid() is not null
    when p_quyen = 'write' and exists (
      select 1 from public.doc_categories c where c.id = p_category_id and c.cap = 'ky_thuat'
    ) then public.has_role('admin', 'iatf_admin')
    else
      public.has_role('admin') or exists (
        select 1 from public.document_permissions dp
        where dp.category_id = p_category_id
          and dp.quyen = p_quyen
          and dp.bo_phan = any(public.current_user_bo_phan())
      )
  end;
$function$;
