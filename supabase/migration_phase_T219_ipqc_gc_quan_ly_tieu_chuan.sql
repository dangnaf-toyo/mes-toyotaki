-- T219: STAGING only. Reuse the existing standards registry and IDs; no data migration.
-- The common manager must also be able to revise legacy machining standards without a step/drawing code.
begin;
create or replace function public.ipqc_gc_luu_tieu_chuan(p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor text;r jsonb;m jsonb;v_id bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','ipqc','nhan_vien_oqc')then
  raise exception 'Không có quyền soạn tiêu chuẩn';
 end if;
 if nullif(trim(p_data->>'phien_ban'),'')is null then raise exception 'Nhập Revision tiêu chuẩn';end if;
 for m in select * from jsonb_array_elements(coalesce(p_data->'muc','[]'))loop
  if coalesce((m->>'da_xac_nhan')::boolean,false)=false then
   raise exception 'Cần kiểm tra và xác nhận từng đặc tính trước khi gửi duyệt';
  end if;
  if (nullif(m->>'lsl','')::numeric)::text in('NaN','Infinity','-Infinity')
    or(nullif(m->>'usl','')::numeric)::text in('NaN','Infinity','-Infinity')then
   raise exception 'Giới hạn kỹ thuật phải là số hữu hạn';
  end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_data->'muc')x
  where nullif(trim(x->>'ma_dac_tinh'),'')is not null
  group by lower(trim(x->>'ma_dac_tinh'))having count(*)>1)then
  raise exception 'Mã đặc tính không được trùng';
 end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 r:=ipqc_btk_luu(p_data->>'ma_sp',p_data,actor,'gia_cong');
 if coalesce((r->>'ok')::boolean,false)=false then raise exception '%',r->>'error';end if;
 v_id:=(r->>'id')::bigint;
 update ipqc_btk set ma_ban_ve=nullif(trim(p_data->>'ma_ban_ve'),''),
  buoc_gia_cong=nullif(trim(p_data->>'buoc_gia_cong'),''),tai_lieu_goc=p_data->'tai_lieu_goc' where id=v_id;
 update ipqc_btk_muc set xac_nhan_boi=auth.uid(),xac_nhan_luc=clock_timestamp()where id_btk=v_id;
 insert into ipqc_gc_tieu_chuan_lich_su(id_btk,nguoi_uid,du_lieu)values(v_id,auth.uid(),jsonb_build_object(
  'tieu_chuan',(select to_jsonb(b)from ipqc_btk b where b.id=v_id),
  'muc',(select jsonb_agg(to_jsonb(history_item)order by history_item.muc_no)
    from ipqc_btk_muc history_item where history_item.id_btk=v_id)));
 return r;
end $$;
revoke all on function public.ipqc_gc_luu_tieu_chuan(jsonb) from public,anon;
grant execute on function public.ipqc_gc_luu_tieu_chuan(jsonb) to authenticated;
commit;
