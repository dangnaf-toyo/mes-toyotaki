-- T278 (R19) — Nhắc NCP đầy đủ + nhắc mở NCP khi IPQC NG.
--  1) Quá hạn trả lời đối sách: nhắc lại MỖI NGÀY (trước chỉ 1 lần).
--  2) Phiếu đang mở, chưa trả lời, chưa có hạn: nhắc Trưởng phòng QC + GĐ SX đặt hạn mỗi ngày.
--  3) Phiếu chờ duyệt đối sách: nhắc Trưởng phòng QC duyệt mỗi ngày.
--  4) IPQC NG sau 24 giờ chưa có NCP, không có yêu cầu tiếp tục SX, chưa đánh dấu "Không cần":
--     nhắc Trưởng phòng QC 1 lần (link mở thẳng form NCP). Chỉ tính NG từ 15/11/2026.
-- Chuông cũ của ngày trước tự đánh dấu xong khi gửi chuông ngày mới / khi phiếu hết điều kiện.
begin;

create table if not exists public.duc_ipqc_ng_khong_ncp (
  id_checkpoint text primary key references public.duc_ipqc_checkpoint(id_checkpoint),
  ly_do text not null,
  nguoi text,
  nguoi_uid uuid,
  luc timestamptz not null default now()
);
alter table public.duc_ipqc_ng_khong_ncp enable row level security;
drop policy if exists duc_ipqc_ng_khong_ncp_doc on public.duc_ipqc_ng_khong_ncp;
create policy duc_ipqc_ng_khong_ncp_doc on public.duc_ipqc_ng_khong_ncp for select to authenticated using (true);
revoke all on public.duc_ipqc_ng_khong_ncp from anon, authenticated;
grant select on public.duc_ipqc_ng_khong_ncp to authenticated;

create or replace function public.ipqc_ng_khong_can_ncp(p_id_checkpoint text, p_ly_do text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  if not has_role('admin', 'qc_manager', 'giam_doc_sx') then
    raise exception 'Chỉ Trưởng phòng QC / GĐ SX / Admin được đánh dấu Không cần NCP';
  end if;
  if nullif(trim(p_ly_do), '') is null then raise exception 'Nhập lý do'; end if;
  if not exists (select 1 from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint and ket_qua = 'NG') then
    raise exception 'Không tìm thấy lần NG %', p_id_checkpoint;
  end if;
  insert into duc_ipqc_ng_khong_ncp (id_checkpoint, ly_do, nguoi, nguoi_uid)
  values (p_id_checkpoint, trim(p_ly_do), duc_ten_nguoi_hien_tai(null), auth.uid())
  on conflict (id_checkpoint) do update set ly_do = excluded.ly_do, nguoi = excluded.nguoi, nguoi_uid = excluded.nguoi_uid, luc = now();
  perform cv_pd_xong('ipqc-ng-ncp:' || p_id_checkpoint);
end $$;
revoke all on function public.ipqc_ng_khong_can_ncp(text, text) from public, anon;
grant execute on function public.ipqc_ng_khong_can_ncp(text, text) to authenticated;

-- Danh sách NG để mở NCP: bỏ lần đã đánh dấu Không cần.
create or replace function public.duc_get_available_ng_checkpoints_for_ncp()
 returns table(id_checkpoint text, ma_may text, ma_sp text, so_khuon text, thoi_diem_kiem_thuc_te timestamptz, mo_ta_de_xuat text)
 language sql stable
as $function$
  select cp.id_checkpoint, cp.ma_may, cp.ma_sp,
    coalesce(cht.so_khuon, ''),
    cp.thoi_diem_kiem_thuc_te,
    duc_build_ipqc_issue_text('NG', cp.loai_kiem, cp.checklist_json, cp.ghi_chu)
  from duc_ipqc_checkpoint cp
  left join duc_ca_hien_tai cht on cht.id_dong = cp.id_dong
  where cp.ket_qua = 'NG'
    and (cp.id_ncp_lien_quan is null or cp.id_ncp_lien_quan = '')
    and cp.thoi_diem_kiem_thuc_te is not null
    and cp.thoi_diem_kiem_thuc_te >= now() - interval '7 days'
    and not exists (select 1 from duc_ipqc_ng_khong_ncp k where k.id_checkpoint = cp.id_checkpoint)
  order by cp.thoi_diem_kiem_thuc_te desc;
$function$;

-- Đánh dấu xong mọi chuông có tiền tố p_tien_to, trừ khoá p_giu (chuông hôm nay).
create or replace function public.ncp_dong_chuong_cu(p_tien_to text, p_giu text)
returns void language sql security definer set search_path = public as $$
  update cv_thong_bao set da_xu_ly = true
  where can_xu_ly and not da_xu_ly and khoa is not null
    and left(khoa, length(p_tien_to)) = p_tien_to
    and khoa is distinct from p_giu;
$$;
revoke all on function public.ncp_dong_chuong_cu(text, text) from public, anon, authenticated;

create or replace function public.ncp_quet_nhac_han()
returns integer language plpgsql security definer set search_path = public as $$
declare r duc_ncp%rowtype; cfg ncp_cau_hinh_nhac_han%rowtype;
 hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
 con_ngay integer; moc text; khoa_moc text; ds uuid[]; ds_moi uuid[]; so_gui integer; tong integer := 0;
 n record; ds_qc uuid[];
begin
 perform pg_advisory_xact_lock(hashtext('ncp_quet_nhac_han'));
 select * into cfg from ncp_cau_hinh_nhac_han where id;
 if not cfg.bat_nhac then return 0; end if;
 ds_qc := cv_pd_ds_role(array['qc_manager']);

 for r in select * from duc_ncp loop
  -- (3) Chờ duyệt đối sách → nhắc Trưởng phòng QC mỗi ngày
  if r.rc_trang_thai_duyet = 'cho_duyet' and r.trang_thai <> 'dong' then
   khoa_moc := 'ncp-cho-duyet:' || r.id_ncp || ':' || hom_nay;
   perform ncp_dong_chuong_cu('ncp-cho-duyet:' || r.id_ncp || ':', khoa_moc);
   select coalesce(array_agg(u), '{}') into ds_moi from unnest(ds_qc) u
    where not exists (select 1 from cv_thong_bao t where t.khoa = khoa_moc and t.nguoi_nhan = u);
   tong := tong + cv_pd_gui(ds_moi, 'ncp', 'nhac_duyet', khoa_moc, 'ncp-detail.html?id=' || r.id_ncp,
    'NCP ' || r.id_ncp || ' — Chờ duyệt Nguyên nhân & Đối sách.', true);
  else
   perform cv_pd_xong('ncp-cho-duyet:' || r.id_ncp || ':', true);
  end if;

  if ncp_da_tra_loi(r) then
   perform cv_pd_xong('ncp-han:' || r.id_ncp || ':', true);
   perform cv_pd_xong('ncp-chua-han:' || r.id_ncp || ':', true);
   continue;
  end if;

  -- (2) Phiếu đang mở chưa có hạn → nhắc đặt hạn mỗi ngày
  if r.han_tra_loi_doi_sach is null then
   if r.trang_thai = 'dong' then continue; end if;
   khoa_moc := 'ncp-chua-han:' || r.id_ncp || ':' || hom_nay;
   perform ncp_dong_chuong_cu('ncp-chua-han:' || r.id_ncp || ':', khoa_moc);
   select coalesce(array_agg(distinct x), '{}') into ds from unnest(ds_qc || cv_pd_ds_role(array['giam_doc_sx'])) x where x is not null;
   select coalesce(array_agg(u), '{}') into ds_moi from unnest(ds) u
    where not exists (select 1 from cv_thong_bao t where t.khoa = khoa_moc and t.nguoi_nhan = u);
   tong := tong + cv_pd_gui(ds_moi, 'ncp', 'nhac_han', khoa_moc, 'ncp-detail.html?id=' || r.id_ncp,
    'NCP ' || r.id_ncp || ' — Chưa có hạn trả lời đối sách, vào đặt hạn.', true);
   continue;
  end if;
  perform cv_pd_xong('ncp-chua-han:' || r.id_ncp || ':', true);

  -- (1) Có hạn: sắp hạn / khẩn / hôm nay 1 lần mỗi mốc; quá hạn nhắc lại mỗi ngày
  con_ngay := r.han_tra_loi_doi_sach - hom_nay;
  moc := case when con_ngay < 0 then 'qua_han' when con_ngay = 0 then 'hom_nay'
    when con_ngay <= cfg.khan_truoc_ngay then 'khan' when con_ngay <= cfg.truoc_han_ngay then 'sap_han' end;
  if moc is null then continue; end if;
  khoa_moc := 'ncp-han:' || r.id_ncp || ':' || r.han_tra_loi_doi_sach || ':' || moc
    || case when moc = 'qua_han' then ':' || hom_nay else '' end;
  perform ncp_dong_chuong_cu('ncp-han:' || r.id_ncp || ':', khoa_moc);
  select coalesce(array_agg(distinct x), '{}') into ds from unnest(
   array[r.nguoi_mo_uid] || cv_pd_ds_ten(r.nguoi_mo_case) || cv_pd_ds_ten(r.nguoi_dam_nhiem_doi_sach) || cv_pd_ds_role(array['giam_doc_sx', 'qc_manager'])
  ) x where x is not null;
  select coalesce(array_agg(u), '{}') into ds_moi from unnest(ds) u
   where not exists (select 1 from cv_thong_bao t where t.khoa = khoa_moc and t.nguoi_nhan = u);
  so_gui := cv_pd_gui(ds_moi, 'ncp', 'nhac_han', khoa_moc, 'ncp-detail.html?id=' || r.id_ncp,
   'NCP ' || r.id_ncp || ' — ' || case moc when 'qua_han' then 'Quá hạn trả lời đối sách ' || (-con_ngay) || ' ngày' when 'hom_nay' then 'Đến hạn trả lời hôm nay' when 'khan' then 'Khẩn: sắp hết hạn trả lời đối sách' else 'Sắp đến hạn trả lời đối sách' end
   || ' (' || to_char(r.han_tra_loi_doi_sach, 'DD/MM/YYYY') || ').', true);
  insert into ncp_nhac_han_log (khoa, id_ncp, han, moc, nguoi_nhan, so_thong_bao)
   values (khoa_moc, r.id_ncp, r.han_tra_loi_doi_sach, moc, ds, so_gui)
   on conflict (khoa) do update set nguoi_nhan = excluded.nguoi_nhan, so_thong_bao = ncp_nhac_han_log.so_thong_bao + excluded.so_thong_bao;
  tong := tong + so_gui;
 end loop;

 -- (4) IPQC NG chưa mở NCP sau 24 giờ
 for n in
  select c.id_checkpoint, c.ma_may, c.ma_sp, c.thoi_diem_kiem_thuc_te t,
   (nullif(c.id_ncp_lien_quan, '') is not null
    or exists (select 1 from duc_ipqc_continue_request q where q.checkpoint_id = c.id_checkpoint)
    or exists (select 1 from duc_ipqc_ng_khong_ncp k where k.id_checkpoint = c.id_checkpoint)) xong
  from duc_ipqc_checkpoint c
  where c.ket_qua = 'NG' and c.thoi_diem_kiem_thuc_te >= timestamptz '2026-11-15 00:00+07'
    and c.thoi_diem_kiem_thuc_te >= now() - interval '7 days'
    and c.thoi_diem_kiem_thuc_te <= now() - interval '24 hours'
 loop
  khoa_moc := 'ipqc-ng-ncp:' || n.id_checkpoint;
  if n.xong then perform cv_pd_xong(khoa_moc); continue; end if;
  select coalesce(array_agg(u), '{}') into ds_moi from unnest(ds_qc) u
   where not exists (select 1 from cv_thong_bao t where t.khoa = khoa_moc and t.nguoi_nhan = u);
  tong := tong + cv_pd_gui(ds_moi, 'ncp', 'ng_chua_ncp', khoa_moc,
   'qc-manager.html?tab=ncp&ncp_ng=' || n.id_checkpoint,
   'IPQC NG ' || coalesce(n.ma_may, '') || ' · ' || coalesce(n.ma_sp, '') || ' lúc '
   || to_char(n.t at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ' chưa mở NCP — mở NCP hoặc chọn Không cần.', true);
 end loop;
 -- NG quá 7 ngày không còn trong danh sách mở NCP → đóng chuông
 update cv_thong_bao set da_xu_ly = true
  where can_xu_ly and not da_xu_ly and khoa like 'ipqc-ng-ncp:%'
    and created_at < now() - interval '6 days';
 return tong;
end $$;
revoke all on function public.ncp_quet_nhac_han() from public, anon, authenticated;

commit;
