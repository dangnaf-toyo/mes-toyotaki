// Read-time directory: no writes, no inference of identity from a person's name.
export function buildDirectory(master, accounts, authUsers, now = Date.now()) {
  const users = new Map(authUsers.map(u => [u.id, u]));
  const rows = new Map();
  const normalize = value => String(value || '').trim().toLowerCase();
  const roles = value => {
    const role = normalize(value);
    return role === 'nhan_vien_oqc' ? ['oqc'] : role ? [role] : [];
  };
  for (const r of master) {
    const code = String(r.ma_nv || r.ten_nhan_vien || '').trim();
    if (!code || r.is_active === false || r.active === false) continue;
    const key = r.ma_nv ? 'code:' + normalize(r.ma_nv) : 'person:' + r.ten_nhan_vien;
    rows.set(key, { id:key, code, name:r.ten_nhan_vien || code, roles:roles(r.vai_tro),
      departments:r.bo_phan ? [r.bo_phan] : [], sources:['master_employees'], linked:false });
  }
  for (const account of accounts) {
    const user = users.get(account.user_id);
    const key = account.username ? 'code:' + normalize(account.username) : 'account:' + account.user_id;
    const old = rows.get(key);
    if (!user || user.deleted_at || (user.banned_until && Date.parse(user.banned_until) > now)) {
      // A coded personnel row explicitly linked to a disabled account is not selectable.
      rows.delete(key); continue;
    }
    const code = String(account.username || account.user_id).trim();
    rows.set(key, { id:key, code, name:account.full_name || old?.name || account.username || 'Tài khoản chưa ghi tên',
      roles:[...new Set([...(old?.roles || []), ...roles(account.role)])],
      departments:[...new Set([...(old?.departments || []), ...(account.bo_phan_phu_trach || [])])],
      sources:[...(old?.sources || []),'user_roles'], linked:!!old });
  }
  return [...rows.values()].sort((a,b)=>a.name.localeCompare(b.name,'vi') || a.id.localeCompare(b.id));
}
