-- cleanup_test_data.sql — เอาข้อมูล [TEST] ออกจากหน้าจอก่อนส่งให้ลูกค้า (ไม่ใช้ DELETE ตาม AGENTS.md)
-- วิธีใช้: แก้อีเมล sales บรรทัด sales_email ด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor
--   1. ยกเลิกการจ่ายทุกรายการในการ์ดของบริษัท [TEST]       payments.is_cancelled = true
--   2. ยกเลิกการ์ดทุกใบของบริษัท [TEST]                    receivables.is_cancelled = true → หายจาก receivable_summary
--   3. ปิดบริษัท [TEST]                                   companies.is_active = false → ไม่อยู่ในรายการเลือก (M4)
-- ทำในนามบัญชี sales (request.jwt.claims) จึงผ่าน RLS และทุกการเปลี่ยนถูกบันทึกใน audit_logs ตามปกติ
-- รันซ้ำได้ (แตะเฉพาะแถวที่ยังไม่ถูกยกเลิก / ยังเปิดอยู่) · เลือกเฉพาะชื่อที่ขึ้นต้นด้วย "[TEST]" เท่านั้น
-- หมายเหตุ: แถวยังอยู่ในฐานข้อมูล (soft delete) และ "ข้อมูล ณ" ในหน้าตารางจะเป็นเวลาที่รันไฟล์นี้

do $$
declare
  sales_email constant text := 'SALES_EMAIL@example.com';
  v_id   uuid := (select id from auth.users where email = sales_email);
  v_role public.user_role;
  n_pay int; n_rec int; n_co int; n_left int;
begin
  if v_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ sales_email ก่อนรัน';
  end if;
  select role into v_role from public.profiles where id = v_id and is_active;
  if v_role is distinct from 'sales' then
    raise exception 'บัญชีนี้ไม่ใช่ sales ที่ active (role = %)', v_role;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- 1. การจ่าย (ก่อนการ์ด: ยกเลิกการจ่ายในการ์ดที่ยกเลิกแล้วก็ทำได้ แต่ทำก่อนให้ชัด)
  update public.payments p
     set is_cancelled = true
    from public.receivables r
    join public.companies c on c.id = r.company_id
   where p.receivable_id = r.id
     and c.name like '[TEST]%'
     and not p.is_cancelled;
  get diagnostics n_pay = row_count;

  -- 2. การ์ด
  update public.receivables r
     set is_cancelled = true
    from public.companies c
   where c.id = r.company_id
     and c.name like '[TEST]%'
     and not r.is_cancelled;
  get diagnostics n_rec = row_count;

  -- 3. บริษัท
  update public.companies
     set is_active = false
   where name like '[TEST]%'
     and is_active;
  get diagnostics n_co = row_count;

  select count(*) into n_left from public.receivable_summary where company_name like '[TEST]%';
  reset role;

  if n_left <> 0 then
    raise exception 'ยังเหลือการ์ด [TEST] ในหน้าจอ % ใบ — ยกเลิกทั้งหมดแล้ว (rollback)', n_left;
  end if;

  raise notice 'ยกเลิกการจ่าย % รายการ, ยกเลิกการ์ด % ใบ, ปิดบริษัท % บริษัท — เหลือการ์ด [TEST] ในหน้าจอ 0 ใบ',
    n_pay, n_rec, n_co;
end $$;

-- ตรวจผล: ต้องได้ 0 ทั้ง 3 ช่อง
select
  (select count(*) from public.receivable_summary where company_name like '[TEST]%') as test_cards_on_screen,
  (select count(*) from public.payments p join public.receivables r on r.id = p.receivable_id
     join public.companies c on c.id = r.company_id
    where c.name like '[TEST]%' and not p.is_cancelled)                            as test_payments_active,
  (select count(*) from public.companies where name like '[TEST]%' and is_active) as test_companies_active;
