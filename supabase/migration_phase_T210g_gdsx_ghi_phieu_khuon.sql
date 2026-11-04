-- T210g — 04/11/2026: Giám đốc SX ghi được phiếu xử lý bất thường (duc_khuon_xlbt_luu) và check sheet bảo dưỡng
-- (duc_khuon_cs_luu). Trước đó chỉ NV bảo dưỡng khuôn / tổ trưởng / QLBP Đúc / admin → GĐSX (260201) mở phiếu bị lỗi
-- "Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi xử lý bất thường". KH tuần vẫn chỉ người lập.
do $p$
declare d text; n text; f text;
begin
  foreach f in array array['public.duc_khuon_xlbt_luu(text,text,text,text,timestamptz,timestamptz,text)', 'public.duc_khuon_cs_luu(bigint,jsonb,boolean)'] loop
    d := pg_get_functiondef(f::regprocedure);
    if position('T210g' in d) = 0 then
      n := replace(d, 'if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then',
                      'if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) and coalesce(v_me.o_role, '''') <> ''giam_doc_sx'' then   -- T210g: GĐSX được ghi');
      n := replace(n, 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi', 'Chỉ nhân viên bảo dưỡng khuôn / tổ trưởng khuôn / QLBP Đúc / Giám đốc SX được ghi');
      if position('T210g' in n) = 0 then raise exception 'T210g: không vá được %', f; end if;
      execute n;
    end if;
  end loop;
end $p$;
