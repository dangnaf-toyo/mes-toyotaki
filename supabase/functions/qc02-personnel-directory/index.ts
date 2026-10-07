import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { buildDirectory } from './directory.mjs';

const cors = {
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'},
});

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors});
  if (req.method !== 'POST') return json({error:'Method không hỗ trợ'},405);
  const jwt = (req.headers.get('Authorization') || '').match(/^Bearer\s+(.+)$/i)?.[1];
  if (!jwt) return json({error:'Cần đăng nhập MES'},401);
  try {
    // Standard Supabase server env only. Never return service credentials to the browser.
    const url = Deno.env.get('SUPABASE_URL');
    const anon = Deno.env.get('SUPABASE_ANON_KEY');
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anon || !service) throw new Error('Missing server configuration');
    const caller = createClient(url,anon,{auth:{persistSession:false}});
    const {data:identity,error:authError} = await caller.auth.getUser(jwt);
    if (authError || !identity?.user) return json({error:'Phiên đăng nhập không hợp lệ'},401);
    const admin = createClient(url,service,{auth:{persistSession:false}});
    const {data:role,error:roleError} = await admin.from('user_roles').select('role').eq('user_id',identity.user.id).maybeSingle();
    if (roleError) throw roleError;
    if (!role?.role) return json({error:'Tài khoản chưa được cấp vai trò MES'},403);
    const readAll = async (table: string, columns: string, sort: string) => {
      const rows=[];
      for(let offset=0;;offset+=500){
        const {data,error}=await admin.from(table).select(columns).order(sort).range(offset,offset+499);
        if(error)throw error;rows.push(...(data || []));if(!data || data.length<500)return rows;
      }
    };
    const [master,accounts] = await Promise.all([
      readAll('master_employees','ma_nv,ten_nhan_vien,vai_tro,bo_phan','ten_nhan_vien'),
      readAll('user_roles','user_id,username,full_name,role,bo_phan_phu_trach','user_id'),
    ]);
    const users=[];
    for(let page=1;;page++){
      const {data,error}=await admin.auth.admin.listUsers({page,perPage:1000});
      if(error)throw error;users.push(...data.users);if(data.users.length<1000)break;
    }
    return json({employees:buildDirectory(master,accounts,users),complete:true});
  } catch {
    return json({error:'Không tải được danh mục nhân sự trung tâm QC'},503);
  }
});
