-- T174 (27/10/2026): sự cố cần IPQC được kết thúc (máy chạy lại) khi lần kiểm IPQC mới nhất là OK HOẶC CẢNH BÁO
-- (trước: chỉ OK — T170). NG / chưa kiểm vẫn bị chặn. Đổi 1 chỗ ở helper duc_ipqc_trang_thai_su_co
-- (duc_resolve_incident / duc_delete_incident / duc_edit_open_incident cùng dùng) + sửa câu thông báo.
-- Không đổi duc_close_f1_incident_if_open (F1 vẫn chỉ TỰ đóng khi IPQC OK).
do $$
declare
  v_fn text; d text; d0 text; r text[];
  v_sua constant text[][] := array[
    ['duc_ipqc_trang_thai_su_co', $a$'ok', coalesce(v_kq = 'OK', false)$a$, $a$'ok', coalesce(v_kq in ('OK', 'CANH_BAO'), false)$a$],
    ['duc_resolve_incident', 'khi IPQC kiểm OK thì bấm', 'khi IPQC kiểm OK hoặc Cảnh báo thì bấm'],
    ['duc_resolve_incident', 'chỉ khi lần kiểm mới nhất là OK mới kết thúc', 'chỉ khi lần kiểm mới nhất là OK hoặc Cảnh báo mới kết thúc'],
    ['duc_delete_incident', 'bắt buộc IPQC OK mới được chạy lại', 'bắt buộc IPQC OK / Cảnh báo mới được chạy lại'],
    ['duc_edit_open_incident', 'Sự cố đang mở bắt buộc IPQC OK', 'Sự cố đang mở bắt buộc IPQC OK / Cảnh báo'],
    ['duc_edit_open_incident', 'khi chưa có kết quả OK', 'khi chưa có kết quả OK / Cảnh báo']
  ];
begin
  foreach v_fn in array array['duc_ipqc_trang_thai_su_co', 'duc_resolve_incident', 'duc_delete_incident', 'duc_edit_open_incident'] loop
    d := pg_get_functiondef(('public.' || v_fn)::regproc); d0 := d;
    for i in 1 .. array_length(v_sua, 1) loop
      if v_sua[i][1] = v_fn then
        if strpos(d, v_sua[i][2]) = 0 then raise exception 'T174: % không có đoạn "%"', v_fn, v_sua[i][2]; end if;
        d := replace(d, v_sua[i][2], v_sua[i][3]);
      end if;
    end loop;
    execute d;
  end loop;
end $$;
