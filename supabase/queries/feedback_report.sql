-- feedback_report.sql — สรุปผลวัดของแต่ละเวอร์ชัน (prd.md ข้อ 11 และ 12)
-- วิธีใช้: รันทั้งไฟล์ใน Supabase SQL Editor (role postgres อ่านได้ทุกแถว ข้าม RLS)
--          ผู้ใช้ในแอปอ่าน app_feedback ได้แค่แถวของตัวเอง จึงไม่มีหน้าจออ่าน feedback ของคนอื่นในแอป
-- ไฟล์นี้อ่านอย่างเดียว ไม่เปลี่ยนข้อมูล · รันซ้ำได้ตลอด
--
-- 5 คำสั่ง:
--   1. ภาพรวมของแต่ละเวอร์ชัน × ตำแหน่ง (จากแบบสอบถาม)
--   2. ตารางผลวัดของ prd.md ข้อ 12 แถวที่มี baseline เทียบได้ตรง ๆ
--   3. ข้อความของคำถามข้อ 2 ทุกรายการ
--   4. คำตอบดิบทุกแถว
--   5. **ความสดของข้อมูล** — เงินเข้าแล้วกี่วันเจ้าของถึงเห็นในระบบ (วัดจาก payments ไม่ใช่แบบสอบถาม)
--
-- ===========================================================================
-- ตัดข้อมูลทดสอบออกจาก **ทุกคำสั่ง** ในไฟล์นี้ (ทั้ง 5 คำสั่ง)
-- ===========================================================================
--   บัญชีทดสอบ:  profiles.display_name มีคำว่า **"ทดสอบ"**  → `p.display_name not like '%ทดสอบ%'`
--   บริษัททดสอบ: companies.name ขึ้นต้นด้วย **'[TEST]'**     → `c.name not like '[TEST]%'`
--
-- ทำไมต้องตัด: `app_feedback` และ `receivable_notes` **ลบไม่ได้และแก้ไม่ได้** (append-only — schema.md 3.6)
-- ถ้าทดลองส่งความคิดเห็นด้วยบัญชีทดสอบ คำตอบนั้นจะอยู่ปนกับคำตอบของลูกค้าจริง **ตลอดไป**
-- และดึงค่าเฉลี่ยของทุกเวอร์ชันเพี้ยนไป ต่างจากการ์ด/การจ่ายที่ยกเลิก (`is_cancelled`) ได้
-- → **ข้อตกลง: บัญชีทดสอบทุกบัญชีต้องมีคำว่า "ทดสอบ" ใน `display_name`** (schema.md 3.1)
--   เพราะเงื่อนไขนี้คือสิ่งเดียวที่กันคำตอบทดสอบออกจากรายงาน ไม่ใช่การลบทีหลัง (ลบไม่ได้)
--   ไม่ใส่อีเมลจริงของลูกค้าลงไฟล์ใน repo จึงกรองด้วยชื่อที่แสดง เหมือนที่กรองบริษัทด้วย '[TEST]'
--
-- baseline "ก่อนมีแอป" ที่วัดจากลูกค้า 6 ต.ค. 2569 (prd.md ข้อ 12):
--   เจ้าของต้องถามฝ่ายขาย / เช็คบัญชีเอง   3 ครั้ง/สัปดาห์   เป้าหมาย 0
--   ฝ่ายขายทำตารางสรุปลูกหนี้            30 นาที/เดือน    เป้าหมาย ไม่ต้องทำแล้ว (0)
-- **คำถามข้อ 4 ถามเป็น "นาทีของเดือนนี้" จึงเทียบกับ 30 นาที/เดือน ได้ตรง ๆ ไม่ต้องแปลงหน่วย**
-- (งานสรุปทำเดือนละครั้งตอนสิ้นเดือน ถ้าถามรายสัปดาห์จะได้ 0 เกือบทุกสัปดาห์แม้ยังไม่มีแอป
--  ตัวเลขจึงวัดอะไรไม่ได้ — ดู prd.md ข้อ 11 และ 12)

-- ---------------------------------------------------------------------------
-- 1. ภาพรวมของแต่ละเวอร์ชัน × ตำแหน่ง — ตารางหลักที่ใช้เทียบข้ามเวอร์ชัน
-- ---------------------------------------------------------------------------
select
  f.app_version                                            as "เวอร์ชัน",
  f.role                                                   as "ตำแหน่ง",
  count(*)                                                 as "จำนวนคำตอบ",
  count(distinct f.user_id)                                as "จำนวนคน",
  min((f.created_at at time zone 'Asia/Bangkok')::date)    as "ตอบครั้งแรก",
  max((f.created_at at time zone 'Asia/Bangkok')::date)    as "ตอบครั้งล่าสุด",
  round(avg(f.helpful), 2)                                 as "ข้อ1 แอปช่วยงาน (เฉลี่ย 1-5)",
  min(f.helpful)                                           as "ข้อ1 ต่ำสุด",
  max(f.helpful)                                           as "ข้อ1 สูงสุด",
  count(f.issues)                                          as "ข้อ2 มีข้อความ (รายการ)",
  -- ข้อ 3 (เจ้าของ) เทียบ baseline 3 ครั้ง/สัปดาห์
  round(avg(f.owner_asks_per_week), 2)                     as "ข้อ3 ถาม/เช็คเอง (ครั้ง/สัปดาห์)",
  case when count(f.owner_asks_per_week) > 0
       then round(avg(f.owner_asks_per_week) - 3, 2) end   as "ข้อ3 ต่างจาก baseline 3",
  -- ข้อ 4 (ฝ่ายขาย) หน่วยเดียวกับ baseline แล้ว (นาที/เดือน) ไม่ต้องแปลง
  round(avg(f.sales_sheet_minutes), 1)                     as "ข้อ4 ทำตารางสรุป (นาที/เดือน)",
  case when count(f.sales_sheet_minutes) > 0
       then round(avg(f.sales_sheet_minutes) - 30, 1) end  as "ข้อ4 ต่างจาก baseline 30 นาที/เดือน",
  count(*) filter (where f.sales_sheet_minutes = 0)        as "ข้อ4 เดือนที่ไม่ต้องทำเลย"
from public.app_feedback f
join public.profiles p on p.id = f.user_id
where p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
group by f.app_version, f.role
order by f.app_version, f.role;

-- ---------------------------------------------------------------------------
-- 2. ตารางผลวัดของ prd.md ข้อ 12 — แถวที่มี baseline เทียบได้ตรง ๆ
--    "ก่อน (กระดาษ)" เป็นค่าที่วัดจากลูกค้า 6 ต.ค. 2569 เขียนไว้คงที่ในคำสั่งนี้
-- ---------------------------------------------------------------------------
select
  x."ตัวชี้วัด",
  x."ก่อน (กระดาษ)",
  x."เวอร์ชัน",
  x."ค่าที่วัดได้",
  x."เป้าหมาย",
  case
    when x.measured is null then 'ยังไม่มีคำตอบ'
    when x.measured = 0 then 'ถึงเป้าหมายแล้ว'
    when x.measured < x.baseline then 'ดีขึ้นจากเดิม'
    when x.measured = x.baseline then 'เท่าเดิม'
    else 'แย่ลงจากเดิม'
  end as "ผล"
from (
  select
    'เจ้าของต้องโทรถาม / เช็คบัญชีเอง (ครั้ง/สัปดาห์)'      as "ตัวชี้วัด",
    '3 ครั้ง/สัปดาห์'                                       as "ก่อน (กระดาษ)",
    f.app_version                                           as "เวอร์ชัน",
    round(avg(f.owner_asks_per_week), 2)::text || ' ครั้ง/สัปดาห์' as "ค่าที่วัดได้",
    '0'                                                     as "เป้าหมาย",
    round(avg(f.owner_asks_per_week), 2)                    as measured,
    3::numeric                                              as baseline
  from public.app_feedback f
  join public.profiles p on p.id = f.user_id
  where f.role = 'owner'
    and f.owner_asks_per_week is not null
    and p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
  group by f.app_version
  union all
  select
    'เวลาที่ฝ่ายขายใช้ทำตารางสรุปต่อเดือน',
    '30 นาที/เดือน',
    f.app_version,
    round(avg(f.sales_sheet_minutes), 1)::text || ' นาที/เดือน',
    'ไม่ต้องทำแล้ว (0)',
    round(avg(f.sales_sheet_minutes), 1),
    30::numeric
  from public.app_feedback f
  join public.profiles p on p.id = f.user_id
  where f.role = 'sales'
    and f.sales_sheet_minutes is not null
    and p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
  group by f.app_version
) x
order by x."ตัวชี้วัด", x."เวอร์ชัน";

-- ---------------------------------------------------------------------------
-- 3. ข้อความของข้อ 2 ทุกรายการ (ที่มาของงานในเวอร์ชันถัดไป) ใหม่ → เก่า
-- ---------------------------------------------------------------------------
select
  f.app_version                                                   as "เวอร์ชัน",
  f.role                                                          as "ตำแหน่ง",
  p.display_name                                                  as "ใคร",
  to_char(f.created_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') as "เมื่อไหร่ (เวลาไทย)",
  f.helpful                                                       as "ข้อ1",
  coalesce(f.owner_asks_per_week, f.sales_sheet_minutes)          as "ข้อ3/4",
  f.issues                                                        as "ข้อ2 อะไรติดขัด / อยากให้เพิ่ม"
from public.app_feedback f
join public.profiles p on p.id = f.user_id
where f.issues is not null
  and p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
order by f.created_at desc;

-- ---------------------------------------------------------------------------
-- 4. ทุกคำตอบแบบดิบ (เผื่อต้องดูรายครั้ง หรือก๊อปไปทำกราฟ)
-- ---------------------------------------------------------------------------
select
  f.app_version                                                   as "เวอร์ชัน",
  f.role                                                          as "ตำแหน่ง",
  p.display_name                                                  as "ใคร",
  to_char(f.created_at at time zone 'Asia/Bangkok', 'YYYY-MM')    as "เดือนที่ตอบ (เวลาไทย)",
  to_char(f.created_at at time zone 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') as "เมื่อไหร่ (เวลาไทย)",
  f.helpful                                                       as "ข้อ1 แอปช่วยงาน",
  f.owner_asks_per_week                                           as "ข้อ3 ครั้ง/สัปดาห์",
  f.sales_sheet_minutes                                           as "ข้อ4 นาที/เดือน",
  f.issues                                                        as "ข้อ2"
from public.app_feedback f
join public.profiles p on p.id = f.user_id
where p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
order by f.app_version, f.role, f.created_at;

-- ---------------------------------------------------------------------------
-- 5. ความสดของข้อมูล — เงินเข้าแล้วกี่วันเจ้าของถึงเห็นในระบบ
--
-- เป็นจุดแข็งหลักของแอป: เดิมเจ้าของรู้ตอนสรุปสิ้นเดือน หรือต้องโทรถามฝ่ายขายเอง
-- (สัมภาษณ์เจ้าของ 6 ต.ค.) ตอนนี้ฝ่ายขายบันทึกปุ๊บเจ้าของเห็นทันทีผ่าน Realtime
-- **เป้าหมาย: ภายใน 1 วัน** (prd.md ข้อ 12)
--
-- วัดจากข้อมูลที่มีอยู่แล้วใน payments ไม่ต้องถามใครและไม่ต้องแก้ database:
--   ความสด (วัน) = วันที่ของ created_at ตามเวลาไทย − paid_date
--     created_at = เวลาที่ฝ่ายขายกดบันทึก (trigger ใส่ให้ แก้ไม่ได้)
--     paid_date  = วันที่เงินเข้าจริง (โอน = วันเงินเข้า, เช็ค = วันเช็คขึ้นเงิน)
--
-- เงื่อนไขการนับ:
--   - ไม่นับการจ่ายที่ถูกยกเลิก (is_cancelled)
--   - **ไม่นับบริษัททดสอบ** (ชื่อขึ้นต้นด้วย '[TEST]')
--   - **ไม่นับการจ่ายที่บันทึกโดยบัญชีทดสอบ** (created_by → display_name มีคำว่า "ทดสอบ")
--     กรองทั้ง 2 ทางเพราะทดสอบด้วยบัญชีทดสอบบนการ์ดจริงก็ทำได้ และตัดได้ทางเดียวไม่พอ
--   - **นับเฉพาะ paid_date ตั้งแต่ 9 ต.ค. 2569 (วันส่งมอบ V0.1)** เพราะการจ่ายก่อนหน้านั้น
--     คือการกรอกย้อนหลังตอนเริ่มใช้แอป ซึ่งทำให้ตัวเลขสูงเกินจริงและไม่ได้สะท้อนการใช้งานปกติ
--   - ค่าติดลบ = บันทึกล่วงหน้าก่อนวันเงินเข้า (เช่น ได้เช็คมาแล้วแต่ยังไม่ถึงวันขึ้นเงิน)
--     ซึ่งเป็นกรณีที่ดีที่สุด (เจ้าของเห็นก่อนเงินเข้าด้วยซ้ำ) จึงนับรวมตามจริง ไม่ปรับเป็น 0
-- ---------------------------------------------------------------------------
with fresh as (
  select
    pm.paid_date,
    ((pm.created_at at time zone 'Asia/Bangkok')::date - pm.paid_date) as lag_days
  from public.payments pm
  join public.receivables r on r.id = pm.receivable_id
  join public.companies   c on c.id = r.company_id
  join public.profiles    p on p.id = pm.created_by
  where not pm.is_cancelled
    and c.name not like '[TEST]%'           -- ตัดบริษัททดสอบ
    and p.display_name not like '%ทดสอบ%'   -- ตัดบัญชีทดสอบ (ดูหัวไฟล์)
    and pm.paid_date >= date '2026-10-09'   -- วันส่งมอบ V0.1 (progress.md "Feedback รอบ 1")
)
select
  coalesce(to_char(f.paid_date, 'IYYY-"W"IW'), 'รวมทุกสัปดาห์')         as "สัปดาห์ของวันเงินเข้า",
  min(f.paid_date)                                                      as "วันแรกของช่วง",
  max(f.paid_date)                                                      as "วันสุดท้ายของช่วง",
  count(*)                                                              as "จำนวนรายการ",
  round(avg(f.lag_days), 2)                                             as "เฉลี่ย (วัน)",
  -- percentile_cont รับได้แค่ double precision / interval (ไม่มี variant ของ numeric)
  -- จึงคืน double precision เสมอ และ round(double, int) ไม่มีใน postgres (42883)
  -- → cast ผลลัพธ์เป็น numeric ก่อน round (cast ที่ order by ไม่ช่วย เพราะถูกบีบกลับเป็น double)
  round((percentile_cont(0.5) within group (order by f.lag_days))::numeric, 2)
                                                                        as "มัธยฐาน (วัน)",
  max(f.lag_days)                                                       as "สูงสุด (วัน)",
  count(*) filter (where f.lag_days <= 1)                               as "ถึงเป้าหมาย (<= 1 วัน)",
  -- nullif: ยังไม่มีการจ่ายตั้งแต่ 9 ต.ค. → rollup ยังคืนแถว "รวมทุกสัปดาห์" ที่ count = 0
  -- ถ้าหารตรง ๆ จะ error division by zero ตอนรันครั้งแรกที่ยังไม่มีข้อมูล
  round(100.0 * count(*) filter (where f.lag_days <= 1) / nullif(count(*), 0), 1)
                                                                        as "ถึงเป้าหมาย (%)"
from fresh f
-- rollup: ได้ทั้งแถวรายสัปดาห์ และแถวสรุปรวมทุกสัปดาห์ (สัปดาห์เป็น null → ป้าย "รวมทุกสัปดาห์")
group by rollup (to_char(f.paid_date, 'IYYY-"W"IW'))
order by "สัปดาห์ของวันเงินเข้า";
