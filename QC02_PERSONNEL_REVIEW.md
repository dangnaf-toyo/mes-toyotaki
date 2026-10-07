# QC02 — danh mục tài khoản / nhân sự

Branch `qc02-rebuild`. Chưa commit/push/deploy; không viết dữ liệu staging hoặc production, không thay RLS/schema/secret/env.

## Nguồn thực tế

- `user_roles`: nguồn tài khoản MES; `user_id` liên kết Auth, `username` mã đăng nhập, `full_name` tên, `role` quyền, `bo_phan_phu_trach` bộ phận. Edge Function admin-create-user tạo Auth user và dòng user_roles, không tạo master_employees.
- `master_employees`: hồ sơ nhân sự của danh mục; khóa theo `ten_nhan_vien`, `ma_nv` optional unique, `vai_tro`, `bo_phan`, `line_may`. Trang danh mục chỉ ghi bảng này và chưa nhập ma_nv.
- Không có FK giữa hai bảng; không có mapping email. Chỉ ghép username = ma_nv khi có mã rõ ràng (trim, không phân biệt hoa thường). Không dùng tên để đoán liên kết.

## Kiểm tra staging thật (chỉ đọc)

Đúng project `jcjbleugnclzsghfpmvk`. Không dùng production.

- Khóa public: đọc được master_employees (56 dòng); user_roles không thấy dòng nào.
- Phiên QC do người dùng cung cấp: role `nhan_vien_oqc`; SELECT master_employees thấy 56 dòng, SELECT user_roles chỉ thấy một dòng của chính mình. Đây là kiểm tra quyền hiệu lực, không phải export pg_policies.
- 56 hồ sơ master hiện chưa có ma_nv; role thấy trong master: nhan_vien, bao_duong_khuon, truong_ca. Không có oqc nên query cũ vai_tro=oqc thiếu tài khoản thực.
- Endpoint qc02-personnel-directory hiện HTTP 404; chưa triển khai.
- Mật khẩu/token không ghi trong báo cáo, Git hoặc output. Script đăng nhập tạm đã xóa; không tạo tài khoản thật.

## Giải pháp chuẩn bị

- Endpoint `supabase/functions/qc02-personnel-directory/index.ts`: POST chỉ đọc, xác thực bearer bằng getUser và kiểm tra caller có role MES. Mọi tài khoản có role MES được đọc danh sách định danh nhân sự cơ bản cho QC. Dùng service client phía server để đọc danh mục/tài khoản, không mở rộng quyền SELECT user_roles của trình duyệt.
- `directory.mjs`: một directory hợp nhất lúc đọc, không sao chép hồ sơ và không tạo bảng. Tài khoản mới có mã hoặc ID tự xuất hiện; nhân sự mới trong master cũng tự xuất hiện. Chỉ ghép khi có ma_nv/username trùng. Hồ sơ chưa có mã vẫn hiển thị riêng; người trùng tên không bị ghép sai.
- Chuẩn hóa role tài khoản `nhan_vien_oqc` thành eligibility `oqc`; giữ role nhân sự khi hồ sơ có liên kết. Các role khác giữ nguyên. Bộ phận đọc đúng field đã có, không tự suy ra bộ phận còn thiếu.
- Auth Admin listUsers chỉ dùng server để loại tài khoản bị khóa/xóa; response không có email, token, auth metadata hoặc service key. Response có mã/tên/roles/departments/sources và thông tin linked. Hồ sơ master độc lập không có trạng thái active trong schema được đọc nên không suy đoán nhân sự đã nghỉ.
- `shared/qc02-data.js`: IQC/NCP/QC Manager/OQC gọi chung endpoint. Refresh khi focus lựa chọn, không cache lâu; gom yêu cầu đang chạy và chống response cũ ghi đè datalist. Endpoint chưa có/lỗi thì cảnh báo danh sách chưa đầy đủ, dùng các dòng có quyền đọc; không khẳng định fallback đã đồng bộ đầy đủ.
- OQC chỉ hiển thị eligibility oqc, Admin không tự thành người kiểm. IQC/NCP giữ phạm vi danh mục chung hiện có. IPQC, người mở phiếu, OQC pallet và approval giữ actor của phiên MesAuth, không cho chọn người khác để thay người thực hiện RPC.

## Mapping còn thiếu

Không cần bổ sung field/bảng cho mục tiêu tự xuất hiện trong dropdown: directory đọc cả hai nguồn trực tiếp. Nếu muốn một hồ sơ duy nhất cho cùng người ở cả hai bảng, cần điền `master_employees.ma_nv` bằng `user_roles.username` hoặc xác nhận một khóa nhân viên ổn định khác. Field ma_nv đã tồn tại trên staging; không cần migration để bổ sung field này. Chưa đoán hoặc tự ghi mapping cho 56 hồ sơ hiện tại. Tài khoản chỉ có email và không username được định danh bằng user_id, không dùng email để ghép người.

## Kiểm tra

- `node tests/qc02-personnel-directory.cjs`: PASS. Giả lập tài khoản mới, role/bộ phận, mapping theo mã, người trùng tên, banned account, response tối thiểu, 401/403/405 và handler chỉ đọc.
- Fixture Chrome offline IQC/IPQC/QC Manager/NCP/OQC daily: 5 PASS, không lỗi JS được fixture ghi nhận. Giả lập thêm tài khoản QCNEW sau khi trang tải, xác nhận xuất hiện ở IQC/OQC/NCP khi focus, tự điền tên OQC. API hoàn toàn giả, không viết DB.
- Parse 54 classic scripts: PASS; diff --check PASS. Deno CLI không có trên máy; handler TypeScript được strip/parse và chạy bằng mocked SDK trong Node, chưa Deno check/runtime integration.
- Chưa test endpoint thật bằng caller QC vì chưa deploy endpoint. Chưa chứng minh các trường hợp RLS/IAM/runtime của Edge Function trên staging bằng tích hợp thật.

## Điều kiện test staging

Sẵn sàng triển khai để test staging theo thứ tự: endpoint Supabase staging trước, kiểm tra caller QC đọc đầy đủ và caller anonymous bị từ chối; sau đó deploy frontend QC02 lên Worker staging. Không deploy frontend đơn lẻ rồi coi đồng bộ đã hoàn tất.

Command dự kiến (CHƯA CHẠY):

```powershell
supabase functions deploy qc02-personnel-directory --project-ref jcjbleugnclzsghfpmvk
```

Giữ JWT verification mặc định; dùng ba biến chuẩn server Supabase đã cung cấp SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY, không tạo secret frontend hoặc đổi secret hiện có. Không cần migration, seed hoặc deploy lại admin-create-user. Không chạm production.

Xác thực getUser dựa trên Supabase Auth server theo tài liệu chính thức: https://supabase.com/docs/reference/javascript/auth-getuser
