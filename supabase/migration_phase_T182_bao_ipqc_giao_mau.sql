-- T182 (29/10/2026): báo IPQC khi trưởng ca bấm "📦 Hoàn thành mẫu & giao QC" (T180) để đến máy kiểm ngay.
--  1. duc_giao_qc_x gửi thông báo chuông MES (cv_thong_bao, nguồn 'ipqc', loại 'giao_mau', cần xử lý) cho mọi
--     tài khoản vai trò ipqc. Khoá 'giao_qc:<máy>:<mã sự cố>'. Lỗi gửi thông báo KHÔNG chặn việc giao QC.
--  2. Thông báo tự chuyển "đã xử lý" khi IPQC kiểm xong checkpoint sau sự cố / đổi khuôn của máy đó,
--     hoặc khi sự cố được đóng (ghi duc_su_co_log).
--  (Trang ipqc.html còn tự kêu chuông / rung / hiện dải cảnh báo — shared/ipqc-bao-mau.js.)

-- ── 1. Gửi thông báo trong duc_giao_qc_x ─────────────────────────────────────
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_giao_qc_x(text,text,text)'::regprocedure), E'\r\n', E'\n');
  if strpos(d, 'T182') = 0 then
    d := replace(d,
      E'  -- Dòng phải có checkpoint chờ kiểm để IPQC thấy trong hàng đợi.\n',
      E'  -- T182: chuông MES cho mọi tài khoản IPQC — lỗi thông báo không được chặn việc giao QC.\n' ||
      E'  begin\n' ||
      E'    perform cv_pd_gui(cv_pd_ds_role(array[''ipqc'']), ''ipqc'', ''giao_mau'', ''giao_qc:'' || c.ma_may || '':'' || v_id, ''ipqc.html'',\n' ||
      E'      ''📦 Máy '' || c.ma_may || '' đã hoàn thành mẫu sau sự cố '' || coalesce(v_loai, '''') ||\n' ||
      E'      case when v_lan > 1 then '' (giao lại lần '' || v_lan || '')'' else '''' end || '' — mời IPQC đến máy kiểm ngay.'', true);\n' ||
      E'  exception when others then raise warning ''duc_giao_qc_x thông báo: %'', sqlerrm;\n' ||
      E'  end;\n\n' ||
      E'  -- Dòng phải có checkpoint chờ kiểm để IPQC thấy trong hàng đợi.\n');
    if strpos(d, 'T182') = 0 then
      -- bản trên DB không còn dòng chú thích gốc → tìm theo câu lệnh kiểm checkpoint
      d := replace(d,
        E'  if not exists (select 1 from duc_ipqc_checkpoint\n',
        E'  -- T182: chuông MES cho mọi tài khoản IPQC — lỗi thông báo không được chặn việc giao QC.\n' ||
        E'  begin\n' ||
        E'    perform cv_pd_gui(cv_pd_ds_role(array[''ipqc'']), ''ipqc'', ''giao_mau'', ''giao_qc:'' || c.ma_may || '':'' || v_id, ''ipqc.html'',\n' ||
        E'      ''📦 Máy '' || c.ma_may || '' đã hoàn thành mẫu sau sự cố '' || coalesce(v_loai, '''') ||\n' ||
        E'      case when v_lan > 1 then '' (giao lại lần '' || v_lan || '')'' else '''' end || '' — mời IPQC đến máy kiểm ngay.'', true);\n' ||
        E'  exception when others then raise warning ''duc_giao_qc_x thông báo: %'', sqlerrm;\n' ||
        E'  end;\n\n' ||
        E'  if not exists (select 1 from duc_ipqc_checkpoint\n');
    end if;
    if strpos(d, 'T182') = 0 then raise exception 'T182: không vá được duc_giao_qc_x'; end if;
    execute d;
  end if;
end $$;

-- ── 2. Tự đánh dấu đã xử lý ──────────────────────────────────────────────────
create or replace function public.duc_giao_qc_tb_xong_cp_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.trang_thai = 'da_kiem' and old.trang_thai is distinct from 'da_kiem'
     and new.loai_kiem in ('sau_su_co', 'doi_khuon') and new.ma_may is not null then
    perform cv_pd_xong('giao_qc:' || new.ma_may || ':', true);
  end if;
  return null;
exception when others then
  raise warning 'duc_giao_qc_tb_xong_cp_trg: %', sqlerrm;
  return null;
end $$;
revoke execute on function public.duc_giao_qc_tb_xong_cp_trg() from public, anon, authenticated;
drop trigger if exists trg_duc_giao_qc_tb_xong on public.duc_ipqc_checkpoint;
create trigger trg_duc_giao_qc_tb_xong after update of trang_thai on public.duc_ipqc_checkpoint
  for each row execute function public.duc_giao_qc_tb_xong_cp_trg();

create or replace function public.duc_giao_qc_tb_xong_log_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.id_su_co is not null and new.ma_may is not null then
    perform cv_pd_xong('giao_qc:' || new.ma_may || ':' || new.id_su_co);
  end if;
  return null;
exception when others then
  raise warning 'duc_giao_qc_tb_xong_log_trg: %', sqlerrm;
  return null;
end $$;
revoke execute on function public.duc_giao_qc_tb_xong_log_trg() from public, anon, authenticated;
drop trigger if exists trg_duc_giao_qc_tb_xong on public.duc_su_co_log;
create trigger trg_duc_giao_qc_tb_xong after insert on public.duc_su_co_log
  for each row execute function public.duc_giao_qc_tb_xong_log_trg();
