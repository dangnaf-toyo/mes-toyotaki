-- T332: Mã dụng cụ đúc thể hiện cả đường kính và chiều dài.
-- Mẫu mới: LOẠI-Φ(3 số)-DÀI(3–4 số)-STT(2 số), vd OL-060-450-01. Chiều dài bắt buộc.
-- 23/11: prod + staging chưa có dụng cụ nào → không cần đổi dữ liệu.
alter table public.duc_dung_cu drop constraint if exists duc_dung_cu_ma_check;
alter table public.duc_dung_cu add constraint duc_dung_cu_ma_check
  check (ma ~ '^(DT|OL|PK|XM|CN|VP)-[0-9]{3}-[0-9]{3,4}-[0-9]{2}$');
alter table public.duc_dung_cu alter column chieu_dai set not null;
