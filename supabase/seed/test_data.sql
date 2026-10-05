-- test_data.sql — ข้อมูลทดสอบของ M3 (บริษัทชื่อขึ้นต้น "[TEST]") ครบทุกสถานะ
-- วิธีใช้: แก้อีเมล sales บรรทัด sales_email ด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor
--         (หลังรัน 001, 002, 003) · เอาออกจากหน้าจอด้วย cleanup_test_data.sql (ยกเลิก/ปิด ไม่ลบ)
-- ทุกการเขียนทำในนามบัญชี sales ผ่าน request.jwt.claims (schema.md 1) + role authenticated จึงผ่าน RLS และ trigger จริง
-- วันที่ทั้งหมดนับจาก "วันนี้" เวลาไทย สถานะจึงถูกเสมอไม่ว่ารันวันไหน
--
-- การ์ดที่ได้ (เดือน = เดือนของวันครบกำหนดจริง, ใช้กรอง):
--   [TEST] ยังไม่จ่าย          เดือนนี้     ยังไม่มีการจ่าย ยังไม่เลยกำหนด
--   [TEST] จ่ายบางส่วน         เดือนนี้     จ่าย 2 ครั้ง (เดือนก่อน + เดือนนี้ → ทดสอบกรองรายการเงินเข้าตามเดือน)
--   [TEST] เลยกำหนด           เดือนนี้     เลยวันครบกำหนดจริงและวันเครดิตแล้ว จ่ายบางส่วน
--   [TEST] ค้างข้ามเดือน 1      เดือนก่อน    จ่ายบางส่วน → ปักบนสุด
--   [TEST] ค้างข้ามเดือน 2      2 เดือนก่อน  ยังไม่จ่าย → ปักบนสุด
--   [TEST] จ่ายแล้ว ตรงเวลา     เดือนนี้     จ่ายครบก่อนกำหนด
--   [TEST] จ่ายแล้ว ช้า         เดือนก่อน    จ่ายครบหลังกำหนด (ไม่ปัก เพราะจ่ายครบแล้ว — เห็นเมื่อเลือกเดือนก่อน / ทุกเดือน)
--   [TEST] เดือนหน้า           เดือนหน้า    ยังไม่จ่าย (ทดสอบเลือกหลายเดือน)
--   [TEST] มีประวัติการแก้ไข     เดือนนี้     แก้การ์ด 2 ครั้ง + update ที่ไม่มีอะไรเปลี่ยน 1 ครั้ง (ต้องไม่โผล่ในประวัติ)
--                                         + แก้การจ่าย 1 ครั้ง + ยกเลิกการจ่าย 1 ครั้ง
--   [TEST] ยกเลิกแล้ว          เดือนนี้     การ์ดถูกยกเลิก → ต้องไม่โผล่ในหน้าจอ
-- ถ้ารันซ้ำหลัง cleanup ชื่อบริษัทจะมีเวลาต่อท้าย (ชื่อบริษัทห้ามซ้ำ)
-- ถ้ายังมีข้อมูล [TEST] ที่ยังไม่ได้ cleanup อยู่ ไฟล์นี้จะหยุดพร้อมข้อความ ไม่ใส่ซ้ำ

-- ---------------------------------------------------------------------------
-- 0. ตั้งผู้ใช้ (temp table อยู่จนปิด session ของ SQL Editor ใช้ใน transaction ถัด ๆ ไป)
-- ---------------------------------------------------------------------------
create temp table if not exists seed_ctx (claims text, suffix text);
truncate seed_ctx;
grant select on seed_ctx to authenticated;  -- อ่านได้หลัง set local role authenticated

do $$
declare
  sales_email constant text := 'SALES_EMAIL@example.com';
  v_id   uuid := (select id from auth.users where email = sales_email);
  v_role public.user_role;
begin
  if v_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ sales_email ก่อนรัน';
  end if;
  select role into v_role from public.profiles where id = v_id and is_active;
  if v_role is distinct from 'sales' then
    raise exception 'บัญชีนี้ไม่ใช่ sales ที่ active (role = %)', v_role;
  end if;
  if exists (select 1 from public.companies where name like '[TEST]%' and is_active) then
    raise exception 'มีข้อมูล [TEST] อยู่แล้ว — รัน cleanup_test_data.sql ก่อนถ้าต้องการใส่ใหม่';
  end if;

  insert into seed_ctx values (
    json_build_object('sub', v_id, 'role', 'authenticated')::text,
    case when exists (select 1 from public.companies where name like '[TEST]%')
         then ' ' || to_char(now() at time zone 'Asia/Bangkok', 'DD/MM HH24:MI')
         else '' end
  );
end $$;

-- ---------------------------------------------------------------------------
-- 1. บริษัท + การ์ด + การจ่าย (transaction เดียว)
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;

do $$
declare
  sfx        constant text := (select suffix from seed_ctx);
  today      constant date := (now() at time zone 'Asia/Bangkok')::date;
  this_month constant date := date_trunc('month', (now() at time zone 'Asia/Bangkok'))::date;
  prev_month constant date := (this_month - interval '1 month')::date;
  next_month constant date := (this_month + interval '1 month')::date;
  -- วันครบกำหนดของการ์ดเดือนนี้: ต้องอยู่ในเดือนนี้และยังไม่ถึง (ถ้าวันนี้ใกล้สิ้นเดือน = วันสุดท้ายของเดือน)
  this_due   constant date := least(today + 10, (next_month - 1));
  c uuid;
  r uuid;
begin
  -- ยังไม่จ่าย
  insert into public.companies (name) values ('[TEST] ยังไม่จ่าย' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, (prev_month - interval '1 month')::date, 45000.00, 60, prev_month, prev_month, this_due);

  -- จ่ายบางส่วน (เดือนก่อน + เดือนนี้)
  insert into public.companies (name) values ('[TEST] จ่ายบางส่วน' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, (prev_month - interval '1 month')::date, 120000.50, 60, prev_month, prev_month, this_due)
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 30000.00, 'transfer', prev_month + 9, '10:42');
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 15250.25, 'cheque', this_month, '14:05');

  -- เลยกำหนด (เดือนนี้ วันจริงเลยมาแล้ว — ถ้าวันนี้เป็นวันที่ 1 จะเป็น "ครบกำหนดวันนี้")
  insert into public.companies (name) values ('[TEST] เลยกำหนด' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, prev_month, 18900.00, 30, today - 40, today - 40, greatest(this_month, today - 3))
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 5000.00, 'transfer', today - 20, '16:48');

  -- ค้างข้ามเดือน 1 (เดือนก่อน จ่ายบางส่วน)
  insert into public.companies (name) values ('[TEST] ค้างข้ามเดือน 1' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, (prev_month - interval '2 month')::date, 75000.00, 60, (prev_month - interval '2 month')::date + 30,
          (prev_month - interval '2 month')::date + 30, prev_month + 14)
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 25000.00, 'transfer', prev_month + 12, '09:20');

  -- ค้างข้ามเดือน 2 (2 เดือนก่อน ยังไม่จ่าย)
  insert into public.companies (name) values ('[TEST] ค้างข้ามเดือน 2' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, (prev_month - interval '3 month')::date, 9876.54, 90, (prev_month - interval '3 month')::date,
          (prev_month - interval '3 month')::date, (prev_month - interval '1 month')::date + 19);

  -- จ่ายแล้ว ตรงเวลา (เดือนนี้ จ่ายครบก่อนวันครบกำหนดจริง)
  insert into public.companies (name) values ('[TEST] จ่ายแล้ว ตรงเวลา' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, prev_month, 32000.00, 30, prev_month + 9, prev_month + 9, this_due)
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 20000.00, 'transfer', prev_month + 20, '11:15');
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 12000.00, 'cheque', today, '13:30');

  -- จ่ายแล้ว ช้า (เดือนก่อน จ่ายครบหลังกำหนด)
  insert into public.companies (name) values ('[TEST] จ่ายแล้ว ช้า' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, (prev_month - interval '1 month')::date, 6359.65, 30, (prev_month - interval '1 month')::date + 14,
          (prev_month - interval '1 month')::date + 14, prev_month + 10)
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 6359.65, 'cheque', least(prev_month + 25, today), '15:00');

  -- เดือนหน้า
  insert into public.companies (name) values ('[TEST] เดือนหน้า' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, this_month, 41578.56, 60, this_month, this_month, next_month + 9);

  -- มีประวัติการแก้ไข (การแก้ไขอยู่ใน transaction ถัดไป ข้อ 2)
  insert into public.companies (name) values ('[TEST] มีประวัติการแก้ไข' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, prev_month, 50000.00, 30, prev_month + 4, prev_month + 4, this_due)
  returning id into r;
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 10000.00, 'transfer', today - 2, '10:00');
  insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
  values (r, 3000.00, 'transfer', today - 1, '09:00');

  -- ยกเลิกแล้ว (สร้างแล้วยกเลิก → ไม่อยู่ใน receivable_summary)
  insert into public.companies (name) values ('[TEST] ยกเลิกแล้ว' || sfx) returning id into c;
  insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
  values (c, prev_month, 1000.00, 30, prev_month, prev_month, this_due)
  returning id into r;
  update public.receivables set is_cancelled = true where id = r;
end $$;
commit;

-- ---------------------------------------------------------------------------
-- 2. ประวัติการแก้ไขของ "[TEST] มีประวัติการแก้ไข" — แยก transaction ทีละขั้น
--    (now() ใน transaction เดียวกันเท่ากันหมด แยกแล้วเวลาใน audit_logs จึงเรียงลำดับได้)
-- ---------------------------------------------------------------------------

-- 2.1 ได้เช็คแล้ว → แก้วันครบกำหนดจริงเป็นวันที่บนเช็ค (prd ข้อ 7) + ยอดรวมเพิ่ม (แสดง 2 ช่องที่เปลี่ยน)
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;
update public.receivables r
   set actual_due_date = r.actual_due_date + 1,
       total_amount    = 52500.00
  from public.companies c
 where c.id = r.company_id and c.name = '[TEST] มีประวัติการแก้ไข' || (select suffix from seed_ctx)
   and not r.is_cancelled;
commit;

-- 2.2 บันทึกซ้ำโดยไม่ได้เปลี่ยนอะไร → audit_logs มีแถว แต่หน้าประวัติต้องไม่แสดง
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;
update public.receivables r
   set credit_days = r.credit_days
  from public.companies c
 where c.id = r.company_id and c.name = '[TEST] มีประวัติการแก้ไข' || (select suffix from seed_ctx)
   and not r.is_cancelled;
commit;

-- 2.3 แก้จำนวนวันเครดิต
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;
update public.receivables r
   set credit_days = 45
  from public.companies c
 where c.id = r.company_id and c.name = '[TEST] มีประวัติการแก้ไข' || (select suffix from seed_ctx)
   and not r.is_cancelled;
commit;

-- 2.4 แก้การจ่าย 10,000 → 12,000 และเปลี่ยนเป็นเช็ค
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;
update public.payments p
   set amount = 12000.00, method = 'cheque'
  from public.receivables r
  join public.companies c on c.id = r.company_id
 where p.receivable_id = r.id and p.amount = 10000.00 and not p.is_cancelled
   and c.name = '[TEST] มีประวัติการแก้ไข' || (select suffix from seed_ctx);
commit;

-- 2.5 ยกเลิกการจ่าย 3,000 (ใส่ผิด)
begin;
select set_config('request.jwt.claims', (select claims from seed_ctx), true);
set local role authenticated;
update public.payments p
   set is_cancelled = true
  from public.receivables r
  join public.companies c on c.id = r.company_id
 where p.receivable_id = r.id and p.amount = 3000.00 and not p.is_cancelled
   and c.name = '[TEST] มีประวัติการแก้ไข' || (select suffix from seed_ctx);
commit;

-- ---------------------------------------------------------------------------
-- 3. ตรวจผล (อ่านอย่างเดียว)
-- ---------------------------------------------------------------------------
select company_name, due_month, balance, is_paid, is_carried_over, days_to_actual_due,
       paid_late_actual_days, paid_late_credit_days
from public.receivable_summary
where company_name like '[TEST]%'
order by is_carried_over desc, actual_due_date;
