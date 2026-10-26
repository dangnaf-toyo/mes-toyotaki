-- T171: iatf_admin được ĐỌC mọi loại tài liệu (như admin).
-- Lỗi: 121203 (iatf_admin) tạo tài liệu kỹ thuật bị "new row violates
-- row-level security policy for table documents" — insert qua được (write
-- ky_thuat = admin/iatf_admin) nhưng .select('id') sau insert cần quyền read,
-- mà read chỉ tự có cho admin; insert document_versions cũng phải thấy được
-- dòng documents. Quyền write/download_source giữ nguyên.

create or replace function public.has_doc_permission(p_category_id uuid, p_quyen text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_quyen = 'write' and exists (
      select 1 from public.doc_categories c where c.id = p_category_id and c.cap = 'ky_thuat'
    ) then public.has_role('admin', 'iatf_admin')
    when p_quyen = 'read' and public.has_role('admin', 'iatf_admin') then true
    else
      public.has_role('admin') or exists (
        select 1 from public.document_permissions dp
        where dp.category_id = p_category_id
          and dp.quyen = p_quyen
          and dp.bo_phan = any(public.current_user_bo_phan())
      )
  end;
$$;
