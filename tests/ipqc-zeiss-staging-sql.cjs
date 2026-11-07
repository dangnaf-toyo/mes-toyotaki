/* Build a rollback-only staging RPC test from values already extracted from the real PDF. */
const fs = require("node:fs"),
  path = require("node:path");
const v = JSON.parse(fs.readFileSync(".review/zeiss-validation.json", "utf8"));
const missingUnits = process.env.MES_ZEISS_MISSING_UNITS === "1";
const featurePayload = v.features.map((m) => ({
  ...m,
  ...(missingUnits ? { don_vi: null } : {}),
  da_xac_nhan: true,
}));
const values = v.parsed.map((c, i) => ({ muc_no: i + 1, mau: 1, gia_tri: c.samples[0].value }));
const trace = v.parsed.map((c, i) => ({
  muc_no: i + 1,
  mau: 1,
  raw: c.samples[0].raw,
  value: c.samples[0].value,
  source: c.source,
  don_vi_nguon: "mm",
  don_vi_mes: "mm",
  don_vi_bo_sung_da_xac_nhan: missingUnits ? "mm" : null,
}));
const quoted = (value) => "'" + JSON.stringify(value).replaceAll("'", "''") + "'::jsonb";
const sql = `-- STAGING jcjbleugnclzsghfpmvk ONLY. All test standards/results are rolled back.
begin;
do $$
declare actor uuid;product text;machine text;standard_id bigint;measurement uuid;r jsonb;payload jsonb;
 test_features jsonb:=${quoted(featurePayload)};test_values jsonb:=${quoted(values)};
 expected_values jsonb:=${quoted(values)};test_trace jsonb:=${quoted(trace)};
 req uuid:=gen_random_uuid();before_standards text;before_features text;before_cast bigint;approved_snapshot jsonb;
begin
 select user_id into actor from user_roles where role='admin' order by user_id limit 1;
 select ma_sp into product from master_products p where not exists(select 1 from ipqc_btk b where b.ma_sp=p.ma_sp and b.cong_doan='gia_cong' and b.trang_thai<>'da_duyet') order by ma_sp limit 1;
 select ma_may into machine from master_machines where bo_phan='Gia công - Sơn' order by ma_may limit 1;
 if actor is null or product is null or machine is null then raise exception 'Missing staging test prerequisites';end if;
 select md5(jsonb_agg(to_jsonb(b)order by b.id)::text)into before_standards from ipqc_btk b;
 select md5(jsonb_agg(to_jsonb(m)order by m.id)::text)into before_features from ipqc_btk_muc m;
 select count(*)into before_cast from ipqc_do_lan;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 r:=ipqc_gc_luu_tieu_chuan(jsonb_build_object('ma_sp',product,'phien_ban','CMM-ROLLBACK-'||req::text,
 'ma_ban_ve','CMM rollback test','buoc_gia_cong','CMM rollback test','ngay_hieu_luc',(now()at time zone'Asia/Ho_Chi_Minh')::date,
 'noi_dung_sua_doi','Rollback verification of real CMM Actual values','so_mau',1,'muc',test_features));
 standard_id:=(r->>'id')::bigint;
 if standard_id is null then raise exception 'Standard create failed: %',r;end if;
 r:=ipqc_tc_duyet('btk',standard_id,'kiem_tra',null,'CMM rollback test');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',standard_id,'phe_duyet',null,'CMM rollback test');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 select jsonb_agg(to_jsonb(m)order by m.muc_no)into approved_snapshot from ipqc_btk_muc m where id_btk=standard_id;
 payload:=jsonb_build_object('request_id',req,'id_btk',standard_id,'ma_sp',product,'ma_may',machine,'ca','Ca ngày','ma_lo','ZEISS-ROLLBACK',
 'nguon_nhap','tu_file','xac_nhan_file',true,'nhan_dien',jsonb_build_object('ten_file','real-calypso.pdf','gia_tri_da_xac_minh',test_trace),'kq',test_values);
 measurement:=ipqc_gc_luu_do(payload);
 if measurement is null or ipqc_gc_luu_do(payload)<>measurement then raise exception 'Save/retry failed';end if;
 if (select count(*)from ipqc_gc_kq where id_lan=measurement)<>jsonb_array_length(expected_values) then raise exception 'Missing actual values';end if;
 if exists(select 1 from jsonb_to_recordset(expected_values)as e(muc_no integer,mau integer,gia_tri numeric)
 left join ipqc_gc_kq k on k.id_lan=measurement and k.muc_no=e.muc_no and k.mau=e.mau
 where k.gia_tri is distinct from e.gia_tri)then raise exception 'Reopened Actual differs from source PDF';end if;
 if not exists(select 1 from ipqc_lan_tong_hop where id=measurement::text and nguon_nhap='tu_file'
 and jsonb_array_length(kq)=jsonb_array_length(expected_values))then raise exception 'Dashboard/source missing';end if;
 if exists(select 1 from ipqc_gc_kq k join ipqc_btk_muc m on m.id_btk=standard_id and m.muc_no=k.muc_no
 where k.id_lan=measurement and k.dat is distinct from ((m.lsl is null or k.gia_tri>=m.lsl)and(m.usl is null or k.gia_tri<=m.usl)))then raise exception 'Wrong OK/NG';end if;
 if (select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where id_btk=standard_id)is distinct from approved_snapshot then raise exception 'Import changed approved features';end if;
 if (select md5(jsonb_agg(to_jsonb(b)order by b.id)::text)from ipqc_btk b where id<>standard_id)is distinct from before_standards then raise exception 'Existing standards changed';end if;
 if (select md5(jsonb_agg(to_jsonb(m)order by m.id)::text)from ipqc_btk_muc m where id_btk<>standard_id)is distinct from before_features then raise exception 'Existing features changed';end if;
 if (select count(*)from ipqc_do_lan)<>before_cast then raise exception 'Casting changed';end if;
end $$;
select 'PASS real Calypso Actual values: staging RPC save/reopen, OKNG, dashboard, idempotence, immutable approved standards, casting isolation; rollback' as result;
rollback;
`;
const output = path.resolve(".review/zeiss-staging-rollback.sql");
fs.writeFileSync(output, sql);
console.log(output);
