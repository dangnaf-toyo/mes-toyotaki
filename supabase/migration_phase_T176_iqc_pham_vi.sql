-- T176 — STAGING ONLY: additive IQC scope / inspector identity. No backfill or deletion.
begin;
alter table public.iqc_lots add column if not exists pham_vi text;
alter table public.iqc_lots add column if not exists nguoi_kiem_id text;
alter table public.iqc_lots add column if not exists nguoi_kiem_ten text;

create or replace function public.iqc_kiem_tra_thong_tin_lot()
returns trigger language plpgsql set search_path=public as $$
begin
  if tg_op='INSERT' or new.pham_vi is distinct from old.pham_vi then
    if new.pham_vi is null or new.pham_vi not in
      ('Bán thành phẩm','Linh kiện đầu vào','Mạ','In','Anode','Đúc','Thành phẩm') then
      raise exception 'Phạm vi IQC bắt buộc, phải thuộc danh sách 7 phạm vi';
    end if;
  end if;
  if tg_op='INSERT' or new.supplier is distinct from old.supplier then
    if new.supplier is null or new.supplier not in ('BRV','HANIN','VIỆT PHÁP','ASAHI','MINGANN') then
      raise exception 'Nhà cung cấp IQC phải thuộc danh sách 5 nhà cung cấp';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.iqc_kiem_tra_thong_tin_lot() from public, anon;
drop trigger if exists iqc_kiem_tra_thong_tin_lot on public.iqc_lots;
create trigger iqc_kiem_tra_thong_tin_lot before insert or update on public.iqc_lots
for each row execute function public.iqc_kiem_tra_thong_tin_lot();
comment on column public.iqc_lots.pham_vi is 'Phạm vi IQC; NULL = dữ liệu cũ chưa xác định, không tự phân loại';
notify pgrst, 'reload schema';
commit;
