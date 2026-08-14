-- ============================================================================
-- Nạp Nguyên liệu (mã NVL) + Số khuôn đang dùng theo từng mã SP, lấy từ Google
-- Sheet "KHSX Master" gốc (cột E "Mã nguyên liệu" + cột J "Số khuôn đang dùng",
-- tab "Master") -- đọc 1 lần khi sheet tạm public 2026-08-14, KHÔNG còn đọc lại
-- Sheet sau bước này. 82/82 mã SP khớp 100% với master_products hiện có.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent — ghi đè
-- đúng giá trị tại thời điểm đọc, không cộng dồn).
-- ============================================================================

update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = null where ma_sp = 'FCC-KPH-01';
update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = null where ma_sp = 'FCC-KPH-02';
update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = null where ma_sp = 'FCC-OUT-01';
update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = null where ma_sp = 'FCC-KFL-01';
update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = '1' where ma_sp = 'FCC-KFM-01';
update public.master_products set nguyen_lieu = 'ADC12-DAK', so_khuon = null where ma_sp = 'FCC-CEN-01';
update public.master_products set nguyen_lieu = 'HD2-HDT', so_khuon = null where ma_sp = 'AST-PAN-01';
update public.master_products set nguyen_lieu = 'HD2-HDT', so_khuon = '22' where ma_sp = 'AST-PAN-02';
update public.master_products set nguyen_lieu = 'HD2-HDT', so_khuon = null where ma_sp = 'AST-CAP-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = null where ma_sp = 'FMC-PNH-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = null where ma_sp = 'FMC-PNL-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'SVP-LOC-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'SVP-BAL-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = null where ma_sp = 'SVP-DIV-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'MIK-389-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'MIK-389-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'MIK-399-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'MIK-398-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'MIK-MT6-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'MIK-MT7-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'MIK-MT7-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'MIK-MT5-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'MIK-MT4-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'IWT-114-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'IWT-115-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'IWT-116-01';
update public.master_products set nguyen_lieu = 'ADC6-CHT', so_khuon = '1' where ma_sp = 'IWT-118-01';
update public.master_products set nguyen_lieu = 'ADC6-CHT', so_khuon = '1' where ma_sp = 'IWT-119-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'SUM-DH3-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'QTL-FOT-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'QTL-FOT-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'FUS-CBN-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'FUS-CBN-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'FUS-UH2-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'EXE-PLY-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'EXE-PLY-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'EXE-PLY-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'EXE-PLY-04';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'EXE-PLT-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'EXE-CEN-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'EXE-OUT-01';
update public.master_products set nguyen_lieu = 'EZDA3-HDT', so_khuon = '1' where ma_sp = 'EXE-SHO-01';
update public.master_products set nguyen_lieu = 'EZDA3-HDT', so_khuon = '1' where ma_sp = 'EXE-SHO-02';
update public.master_products set nguyen_lieu = 'EZDA3-HDT', so_khuon = '1' where ma_sp = 'EXE-SHO-03';
update public.master_products set nguyen_lieu = 'EZDA3-MET', so_khuon = '1' where ma_sp = 'BPH-SHO-01';
update public.master_products set nguyen_lieu = 'EZDA3-MET', so_khuon = '1' where ma_sp = 'BPH-SHO-02';
update public.master_products set nguyen_lieu = 'EZDA3-MET', so_khuon = '1' where ma_sp = 'BPH-SHO-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-04';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-05';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GWI-06';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-04';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-05';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-06';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-07';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GJT-08';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GMN-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GMN-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GMN-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'OKA-GMN-06';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'COS-GZ5-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'COS-GZ5-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'COS-CVR-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '2' where ma_sp = 'SOJ-LIG-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-MOT-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1,2' where ma_sp = 'TTI-MOT-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-MOT-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-MOT-04';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1,2' where ma_sp = 'TTI-MOT-05';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-HSG-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-PUM-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-PUM-02';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'TTI-PUM-03';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'STW-COV-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'STW-COV-02';
update public.master_products set nguyen_lieu = 'EZDA3-HDT', so_khuon = '1' where ma_sp = 'YHS-HAN-01';
update public.master_products set nguyen_lieu = 'ADC12-CHT', so_khuon = '1' where ma_sp = 'PRE-W99-01';
