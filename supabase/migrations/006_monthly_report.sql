-- 006_monthly_report.sql — V2
-- หน้า "สรุปรายเดือน" (prd.md ข้อ 6.1 · schema.md ข้อ 4.3): 3 view อ่านอย่างเดียว
--   monthly_report        1 แถวต่อ 1 การ์ด + ลำดับในเดือนนั้น (เรียงตามวันครบกำหนดจริง)
--   monthly_report_total  1 แถวต่อ 1 เดือน = แถว "ยอดรวม" ท้ายตาราง
--   report_asof           1 แถว: "วันนี้" และเวลาที่ดู ตามเวลาไทย (หัวรายงาน + บรรทัดยอดค้างข้ามเดือน)
--
-- **ยอดเงินทุกตัว รวมแถวยอดรวม คำนวณใน database ที่นี่** แอปห้ามบวก/เทียบเงินเอง (AGENTS.md)
-- แอปทำได้แค่กรองแถวตาม due_month และจัดรูปแบบตัวเลข (เหมือนหน้าตารางที่กรองเดือนในแอปอยู่แล้ว)
--
-- ไม่มีตารางใหม่ ไม่แตะ RLS / trigger / view เดิม และไม่ต้องเพิ่มอะไรใน publication ของ Realtime
-- (หน้ารายงาน subscribe 5 ตารางเดิมผ่าน useLiveReload แล้วโหลดจาก view เหล่านี้ใหม่ — architecture.md ข้อ 7)
--
-- ต้องรัน 001–005 ก่อน · รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว
-- (ต้องการเปลี่ยน → เขียน 007_*.sql) · ชุดตรวจ PASS/FAIL: supabase/tests/v2_checks.sql
--
-- สิทธิ์ (schema.md ข้อ 5): **owner และ sales อ่านได้ทั้งคู่ ไม่มีใครเขียนได้**
--   - security_invoker = true → ใช้ RLS ของคนที่อ่าน (เหมือน receivable_summary)
--     policy *_select_active_users ของ receivables / companies / payments จึงบังคับเองว่า
--     anon และผู้ใช้ที่ is_active = false (my_role() เป็น null) ไม่เห็นแถวใดเลย
--   - grant แค่ select ไม่มี insert / update / delete ให้ใคร → เรียก API ตรงก็เขียนไม่ได้ (42501)
--     และ view เหล่านี้ไม่ auto-updatable อยู่แล้ว (สร้างบน receivable_summary ที่มี join / lateral / group by)

-- ---------------------------------------------------------------------------
-- 1. monthly_report — แถวของตาราง
--    เดือนของรายงาน = เดือนของ actual_due_date (due_month ของ receivable_summary — prd.md ข้อ 7)
--    ลำดับ: row_number() ต่อเดือน เรียง actual_due_date เร็ว → ช้า
--           ตัดเสมอด้วย company_name แล้ว id เพื่อให้ลำดับคงที่เมื่อวันครบกำหนดเท่ากัน
--    การ์ดที่จ่ายครบยังอยู่ในตาราง (balance = 0.00) และไม่มีคอลัมน์สถานะ (ลูกค้าสั่ง 19 ต.ค.)
--    การ์ดที่ยกเลิกไม่โผล่ เพราะ receivable_summary กรอง is_cancelled ออกแล้ว
--
--    **ไม่มีคอลัมน์ is_carried_over ที่นี่โดยเจตนา** (ลูกค้าสั่ง 19 ต.ค. ข้อ 4):
--    is_carried_over ของ receivable_summary ผูกกับ "เดือนปัจจุบัน" ถ้าเอามาทำบล็อก
--    "ยอดค้างข้ามเดือน" ใต้ตาราง แล้วผู้ใช้เลือกเดือนที่ผ่านมา การ์ดใบเดิมจะโผล่
--    ทั้งในตารางและในบล็อก (ซ้ำกัน)
--    บล็อกใต้ตารางต้องใช้ **due_month < เดือนที่เลือก  และ  not is_paid** เท่านั้น
--    จึงส่ง is_paid มาให้แอปใช้ตัดสิน แอปไม่ต้องเทียบยอดเงินเองเลย
-- ---------------------------------------------------------------------------
create view public.monthly_report
with (security_invoker = true)
as
select
  s.due_month,
  row_number() over (
    partition by s.due_month
    order by s.actual_due_date, s.company_name, s.id
  )::int            as seq,
  s.id              as receivable_id,
  s.company_name,
  s.credit_days,
  s.account_month,
  s.total_amount,
  s.balance,
  s.is_paid,
  s.actual_due_date
from public.receivable_summary s;

comment on view public.monthly_report is
  'แถวของหน้าสรุปรายเดือน (schema.md 4.3): 1 แถวต่อ 1 การ์ด + ลำดับในเดือน · อ่านอย่างเดียว · ไม่มี is_carried_over โดยเจตนา (บล็อกค้างข้ามเดือนใช้ due_month < เดือนที่เลือก and not is_paid)';

-- ---------------------------------------------------------------------------
-- 2. monthly_report_total — แถว "ยอดรวม" ท้ายตาราง (1 แถวต่อ 1 เดือน)
--    RLS ของตารางต้นทางถูกบังคับก่อน group by → ผลรวมนับแค่แถวที่ผู้ใช้มีสิทธิ์อ่าน
--    เดือนที่ไม่มีการ์ดเลยจะไม่มีแถวที่นี่ → แอปแสดงสถานะ "ไม่มีการ์ดในเดือนนี้"
--    ไม่ใช่เขียนเลข 0 ขึ้นมาเอง (ตัวเลขทุกตัวบนกระดาษต้องมีที่มาจาก database)
-- ---------------------------------------------------------------------------
create view public.monthly_report_total
with (security_invoker = true)
as
select
  s.due_month,
  count(*)::int                      as card_count,
  sum(s.total_amount)::numeric(14,2) as total_amount_sum,
  sum(s.balance)::numeric(14,2)      as balance_sum
from public.receivable_summary s
group by s.due_month;

comment on view public.monthly_report_total is
  'ยอดรวมของจำนวนเงินและยอดคงเหลือ แยกตามเดือนครบกำหนด = แถวสุดท้ายของตารางสรุปรายเดือน (schema.md 4.3)';

-- ---------------------------------------------------------------------------
-- 3. report_asof — "วันนี้" และเวลาที่ดู ตามเวลาไทย (schema.md ข้อ 1)
--    ใช้ที่หัวรายงาน ("ดู ณ <วันที่> <เวลา> น. โดย <ชื่อผู้ใช้>")
--    และบรรทัด "ยอดค้างข้ามเดือน ณ วันที่ <วันนี้>"
--    เอามาจาก database ไม่ใช่นาฬิกาเครื่อง เพราะมือถือตั้งเวลา/โซนเวลาเพี้ยนได้
--    แล้ววันที่บนกระดาษที่ลูกค้าเก็บไว้จะผิด
--
--    view นี้ไม่ได้อ่านตารางไหน จึงไม่มี RLS มาช่วยกรอง → เขียนเงื่อนไขสิทธิ์เอง
--    my_role() เป็น null = ไม่มี profile หรือ is_active = false → ได้ 0 แถว
-- ---------------------------------------------------------------------------
create view public.report_asof
with (security_invoker = true)
as
select
  (now() at time zone 'Asia/Bangkok')::date as today,
  now()                                     as viewed_at
where (select public.my_role()) is not null;

comment on view public.report_asof is
  'วันนี้ (เวลาไทย) + เวลาที่ดู สำหรับหัวรายงานและบรรทัดยอดค้างข้ามเดือน (schema.md 4.3) · อ่านได้เฉพาะผู้ใช้ที่ใช้งานอยู่';

-- ---------------------------------------------------------------------------
-- 4. สิทธิ์: อ่านได้ทั้ง owner และ sales · ไม่มีใครเขียนได้ · anon ไม่ได้อะไรเลย
-- ---------------------------------------------------------------------------
revoke all on table public.monthly_report, public.monthly_report_total, public.report_asof
  from anon, authenticated;
grant select on table public.monthly_report, public.monthly_report_total, public.report_asof
  to authenticated;

-- ตรวจผลเบื้องต้น: ต้องได้ PASS ทุกช่องของทั้ง 3 view (ชุดตรวจเต็มอยู่ใน supabase/tests/v2_checks.sql)
select
  x.viewname                                                                      as "view",
  case when c.relkind = 'v' then 'PASS' else 'FAIL (ไม่ใช่ view)' end             as "เป็น view",
  case when c.reloptions::text like '%security_invoker=true%'
       then 'PASS' else 'FAIL (ไม่ได้ตั้ง security_invoker)' end                  as "ใช้ RLS ของคนอ่าน",
  case when has_table_privilege('authenticated', c.oid, 'select')
       then 'PASS' else 'FAIL (authenticated อ่านไม่ได้)' end                     as "อ่านได้",
  case when has_table_privilege('authenticated', c.oid, 'insert')
        or has_table_privilege('authenticated', c.oid, 'update')
        or has_table_privilege('authenticated', c.oid, 'delete')
       then 'FAIL (มีสิทธิ์เขียน)' else 'PASS (อ่านอย่างเดียว)' end               as "ห้ามเขียน",
  case when has_table_privilege('anon', c.oid, 'select')
       then 'FAIL (anon อ่านได้)' else 'PASS' end                                 as "anon ไม่เห็น"
from (values ('monthly_report'), ('monthly_report_total'), ('report_asof')) as x(viewname)
join pg_class c on c.oid = ('public.' || x.viewname)::regclass
order by x.viewname;
