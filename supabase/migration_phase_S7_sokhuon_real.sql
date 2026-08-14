-- ============================================================================
-- Số khuôn THẬT theo mã SP (do người dùng cung cấp trực tiếp 2026-08-14, không
-- phải suy ra từ Google Sheet) -- thay giá trị tạm (chỉ là số lượng khuôn, VD
-- '1'/'2') đã nạp ở migration_phase_S6_data_nguyenlieu_sokhuon.sql bằng mã khuôn
-- thật (VD 'KPH #17-18'). Nhiều SP dùng chung 1 mã khuôn tổ hợp (VD 'GWI #1' của
-- 6 mã OKA-GWI-01..06) -- KHÔNG ghi vào duc_shot_khuon (khoá chính ma_khuon sẽ
-- xung đột nếu nhiều SP trỏ cùng 1 mã), chỉ lưu ở master_products.so_khuon (text
-- gợi ý tự điền khi in tem, không phải khoá quan hệ).
-- 8 mã SP KHÔNG có trong danh sách người dùng cung cấp lần này (còn giữ giá trị
-- tạm cũ) -- điền bổ sung sau nếu có: STW-COV-02, FCC-KFL-01, BPH-SHO-02,
-- BPH-SHO-03, AST-CAP-01, BPH-SHO-01, SVP-DIV-01, STW-COV-01.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

update public.master_products set so_khuon = 'PAN #FR24, PAN #FR25, PAN #FR26' where ma_sp = 'AST-PAN-01';
update public.master_products set so_khuon = 'PAN #S22' where ma_sp = 'AST-PAN-02';
update public.master_products set so_khuon = 'CVR #1' where ma_sp = 'COS-CVR-01';
update public.master_products set so_khuon = 'GZ54 #1' where ma_sp = 'COS-GZ5-01';
update public.master_products set so_khuon = 'GZ55 #1' where ma_sp = 'COS-GZ5-02';
update public.master_products set so_khuon = 'CEN #2' where ma_sp = 'EXE-CEN-01';
update public.master_products set so_khuon = 'OUT #2' where ma_sp = 'EXE-OUT-01';
update public.master_products set so_khuon = 'PLAT #3' where ma_sp = 'EXE-PLT-01';
update public.master_products set so_khuon = 'BJJ #2' where ma_sp = 'EXE-PLY-01';
update public.master_products set so_khuon = 'FIX #1' where ma_sp = 'EXE-PLY-02';
update public.master_products set so_khuon = 'SLD #1' where ma_sp = 'EXE-PLY-03';
update public.master_products set so_khuon = 'T41 #1' where ma_sp = 'EXE-PLY-04';
update public.master_products set so_khuon = '3B54 #1' where ma_sp = 'EXE-SHO-01';
update public.master_products set so_khuon = '3B53 #1' where ma_sp = 'EXE-SHO-02';
update public.master_products set so_khuon = '3B69#1' where ma_sp = 'EXE-SHO-03';
update public.master_products set so_khuon = 'CEN #33-36' where ma_sp = 'FCC-CEN-01';
update public.master_products set so_khuon = 'KFM #67-70' where ma_sp = 'FCC-KFM-01';
update public.master_products set so_khuon = 'KPH #17-18' where ma_sp = 'FCC-KPH-01';
update public.master_products set so_khuon = 'KPH #13-14, KPH #15-16' where ma_sp = 'FCC-KPH-02';
update public.master_products set so_khuon = 'K09 #45-46, K09 #47-48' where ma_sp = 'FCC-OUT-01';
update public.master_products set so_khuon = 'PAN #H4' where ma_sp = 'FMC-PNH-01';
update public.master_products set so_khuon = 'PAN #L2' where ma_sp = 'FMC-PNL-01';
update public.master_products set so_khuon = 'CBNL #1' where ma_sp = 'FUS-CBN-01';
update public.master_products set so_khuon = 'CBNR #1' where ma_sp = 'FUS-CBN-02';
update public.master_products set so_khuon = 'UH2L #1' where ma_sp = 'FUS-UH2-01';
update public.master_products set so_khuon = '114 #1' where ma_sp = 'IWT-114-01';
update public.master_products set so_khuon = '115 #1' where ma_sp = 'IWT-115-01';
update public.master_products set so_khuon = '116 #1' where ma_sp = 'IWT-116-01';
update public.master_products set so_khuon = '118 #1' where ma_sp = 'IWT-118-01';
update public.master_products set so_khuon = '119 #1' where ma_sp = 'IWT-119-01';
update public.master_products set so_khuon = '3890 #2' where ma_sp = 'MIK-389-01';
update public.master_products set so_khuon = '3891 #2' where ma_sp = 'MIK-389-02';
update public.master_products set so_khuon = '3989 #2' where ma_sp = 'MIK-398-01';
update public.master_products set so_khuon = '3990 #2' where ma_sp = 'MIK-399-01';
update public.master_products set so_khuon = 'MT45 #1' where ma_sp = 'MIK-MT4-01';
update public.master_products set so_khuon = 'MT55 #1' where ma_sp = 'MIK-MT5-01';
update public.master_products set so_khuon = 'MT66 #1' where ma_sp = 'MIK-MT6-01';
update public.master_products set so_khuon = 'MT77 #1' where ma_sp = 'MIK-MT7-01';
update public.master_products set so_khuon = 'MT77 #1' where ma_sp = 'MIK-MT7-02';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-01';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-02';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-03';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-04';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-05';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-06';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-07';
update public.master_products set so_khuon = 'GJT #1' where ma_sp = 'OKA-GJT-08';
update public.master_products set so_khuon = 'GMN #1' where ma_sp = 'OKA-GMN-01';
update public.master_products set so_khuon = 'GMN #1' where ma_sp = 'OKA-GMN-02';
update public.master_products set so_khuon = 'GMN #1' where ma_sp = 'OKA-GMN-03';
update public.master_products set so_khuon = 'GMN #1' where ma_sp = 'OKA-GMN-06';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-01';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-02';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-03';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-04';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-05';
update public.master_products set so_khuon = 'GWI #1' where ma_sp = 'OKA-GWI-06';
update public.master_products set so_khuon = 'PRE #1' where ma_sp = 'PRE-W99-01';
update public.master_products set so_khuon = 'FOTL #1' where ma_sp = 'QTL-FOT-01';
update public.master_products set so_khuon = 'FOTR #1' where ma_sp = 'QTL-FOT-02';
update public.master_products set so_khuon = 'LIGO #2' where ma_sp = 'SOJ-LIG-01';
update public.master_products set so_khuon = 'DH36 #1' where ma_sp = 'SUM-DH3-01';
update public.master_products set so_khuon = 'BAL #1' where ma_sp = 'SVP-BAL-01';
update public.master_products set so_khuon = 'LOCK #1' where ma_sp = 'SVP-LOC-01';
update public.master_products set so_khuon = '4001 #1' where ma_sp = 'TTI-HSG-01';
update public.master_products set so_khuon = '9001 #1' where ma_sp = 'TTI-MOT-01';
update public.master_products set so_khuon = '9002 #1, 9002 #2' where ma_sp = 'TTI-MOT-02';
update public.master_products set so_khuon = '9003 #1' where ma_sp = 'TTI-MOT-03';
update public.master_products set so_khuon = '8001 #1' where ma_sp = 'TTI-MOT-04';
update public.master_products set so_khuon = '8002 #1, 8002 #2' where ma_sp = 'TTI-MOT-05';
update public.master_products set so_khuon = '1012 #1' where ma_sp = 'TTI-PUM-01';
update public.master_products set so_khuon = '1014 #1' where ma_sp = 'TTI-PUM-02';
update public.master_products set so_khuon = '1016 #1' where ma_sp = 'TTI-PUM-03';
update public.master_products set so_khuon = 'HAN #1' where ma_sp = 'YHS-HAN-01';
