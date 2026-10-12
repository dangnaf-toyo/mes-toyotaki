-- ============================================================================
-- Giai đoạn T92 — Thông tin khuôn chỉ admin được thay đổi.
--
-- Trước T92: duc_configure_mold / duc_rename_khuon / duc_xoa_khuon (security
-- definer) KHÔNG kiểm tra vai trò — mọi tài khoản đăng nhập gọi được;
-- duc_khuon_doi_tinh_trang / duc_khuon_dat_uu_tien cho NV bảo dưỡng khuôn +
-- QLBP Đúc + admin. Bảng duc_shot_khuon thì RLS đã chỉ admin ghi.
--
-- T92: cả 5 hàm chỉ admin (has_role('admin')). Giao diện sửa/xoá/tình trạng/
-- ưu tiên chuyển sang Quản lý danh mục → tab Khuôn (chỉ admin);
-- quan-ly-khuon.html chỉ còn xem + hạng mục check sheet + vấn đề khuôn.
--
-- Chèn đoạn kiểm tra vào ngay sau "begin" đầu tiên của thân hàm đang có trên
-- project (không chép lại cả hàm — duc_xoa_khuon prod/staging đang khác nhau).
-- Đã có dấu "T92 chỉ admin" thì bỏ qua → chạy lại nhiều lần an toàn.
-- ============================================================================

do $$
declare
  r record;
  v_def text;
  v_pos int;
  v_guard text;
  v_viec text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_result(p.oid) as ret
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public'
      and p.proname in ('duc_configure_mold', 'duc_rename_khuon', 'duc_xoa_khuon',
                        'duc_khuon_doi_tinh_trang', 'duc_khuon_dat_uu_tien')
  loop
    if r.ret <> 'jsonb' then
      raise exception 'T92: % trả về % (cần jsonb)', r.proname, r.ret;
    end if;
    v_def := pg_get_functiondef(r.oid);
    if position('T92 chỉ admin' in v_def) > 0 then
      continue;
    end if;
    v_viec := case r.proname
      when 'duc_configure_mold'       then 'khai báo / sửa khuôn'
      when 'duc_rename_khuon'         then 'đổi mã khuôn'
      when 'duc_xoa_khuon'            then 'xoá khuôn'
      when 'duc_khuon_doi_tinh_trang' then 'đổi tình trạng khuôn'
      else                                 'đặt thứ tự ưu tiên khuôn'
    end;
    v_guard := E'\n  -- T92 chỉ admin\n  if not has_role(''admin'') then\n    return jsonb_build_object(''ok'', false, ''error'', ''Chỉ admin được ' || v_viec || E''');\n  end if;';
    -- "begin" đầu tiên sau phần mở thân hàm $function$.
    v_pos := position('$function$' in v_def);
    v_pos := v_pos - 1 + length((regexp_match(lower(substr(v_def, v_pos)), '^(.*?\mbegin\M)'))[1]);
    if v_pos is null then
      raise exception 'T92: không tìm thấy begin trong %', r.proname;
    end if;
    execute substr(v_def, 1, v_pos) || v_guard || substr(v_def, v_pos + 1);
  end loop;
end $$;

-- Kiểm tra: phải ra 5 dòng, co_kiem_tra = true.
select p.proname, position('T92 chỉ admin' in p.prosrc) > 0 as co_kiem_tra
from pg_proc p join pg_namespace s on s.oid = p.pronamespace
where s.nspname = 'public'
  and p.proname in ('duc_configure_mold', 'duc_rename_khuon', 'duc_xoa_khuon',
                    'duc_khuon_doi_tinh_trang', 'duc_khuon_dat_uu_tien')
order by 1;
