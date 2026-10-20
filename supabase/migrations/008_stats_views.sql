-- 008_stats_views.sql — V2
-- หน้า "สถิติ" (/stats) — prd.md ข้อ 6.3 · schema.md ข้อ 4.5
-- ที่มา: feedback อาจารย์ 20 ต.ค. 2569 — "ให้มีหน้าสรุปเป็นสถิติ วิเคราะห์ลูกค้า"
--
-- 6 view อ่านอย่างเดียว ไม่มีตารางใหม่ ไม่แตะ RLS / trigger / view เดิม:
--   stats_cards                 ฐานร่วม = "การ์ดที่นับในสถิติ" (ที่เดียวที่นิยาม)
--   stats_overview              1 แถว: ภาพรวม ณ วันนี้ + ขอบเขตข้อมูล (data_since)
--   stats_collection_by_month   ส่วน 1: เก็บเงินของเดือนนั้นได้กี่ % (1 แถวต่อ 1 เดือน)
--   stats_aging                 ส่วน 2: อายุหนี้ค้าง ณ วันนี้ (4 แถวคงที่เสมอ)
--   stats_company_behavior      ส่วน 3: พฤติกรรมการจ่ายของแต่ละบริษัท
--   stats_company_balance       ส่วน 4: ยอดค้างกระจุกที่ใคร (เรียงมาก → น้อย)
--
-- **ยอดเงิน / % / ค่าเฉลี่ย / การจัดกลุ่ม / ลำดับ คำนวณในนี้ทั้งหมด** (AGENTS.md)
-- แอปทำได้แค่กรองแถวตามเดือนที่เลือก เลือกแสดง 5 อันดับแรก และจัดรูปแบบตัวเลข
-- ห้ามบวก / หาร / เทียบเงินหรือเปอร์เซ็นต์ใน JavaScript แม้แต่ความกว้างของแถบกราฟ
--
-- expand เท่านั้น: เพิ่ม view ใหม่ 6 ตัว ไม่มี DDL บนตารางไหนเลย และไม่ได้แก้ view เดิม
-- → แอปที่ deploy อยู่ (V2 ปัจจุบัน) ทำงานต่อได้ 100% ระหว่างที่ยังไม่ deploy หน้าใหม่
-- ไม่ต้องเพิ่มอะไรใน publication ของ Realtime (หน้านี้ subscribe 5 ตารางเดิมผ่าน useLiveReload
-- แล้วโหลด view เหล่านี้ใหม่ — architecture.md ข้อ 7)
--
-- ต้องรัน 001–007 ก่อน · รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว
-- (ต้องการเปลี่ยน → เขียน 009_*.sql) · ชุดตรวจ PASS/FAIL: supabase/tests/stats_checks.sql
--
-- สิทธิ์ (schema.md ข้อ 5): **owner และ sales อ่านได้ทั้งคู่ ไม่มีใครเขียนได้**
--   - security_invoker = true → ใช้ RLS ของคนที่อ่าน เหมือน receivable_summary / monthly_report
--     policy *_select_active_users ของ receivables / companies / payments จึงบังคับเองว่า
--     anon และผู้ใช้ที่ is_active = false (my_role() เป็น null) ไม่เห็นแถวใดเลย
--   - grant แค่ select ไม่มี insert / update / delete ให้ใคร → เรียก API ตรงก็เขียนไม่ได้ (42501)
--     และ view เหล่านี้ไม่ auto-updatable อยู่แล้ว (มี join / lateral / group by / window)
--   - ต้อง grant select ให้ stats_cards ด้วย เพราะ security_invoker ตรวจสิทธิ์ของ "คนที่อ่าน"
--     ทุกชั้นที่ซ้อนกัน ไม่ใช่สิทธิ์ของเจ้าของ view

-- ---------------------------------------------------------------------------
-- 1. stats_cards — ฐานร่วมของทุก view ในไฟล์นี้
--    นิยาม "การ์ดที่นับในสถิติ" ไว้ที่เดียว: ถ้ากฎเปลี่ยน แก้ที่นี่แล้วถูกทั้งหน้า
--      - การ์ดที่ยกเลิก **ไม่นับ** (receivable_summary กรอง is_cancelled ออกอยู่แล้ว)
--      - บริษัท [TEST] **ไม่นับ** (ข้อมูลทดสอบ / เดโม — AGENTS.md)
--        ผลที่ตามมาและเขียนเป็นกฎไว้ใน AGENTS.md แล้ว: **บริษัทจริงห้ามชื่อขึ้นต้นด้วย [TEST]**
--        ไม่งั้นจะหายจากทุกสถิติ แต่ยังโผล่ในหน้าตารางและรายงานรายเดือน (อ่านตัวเลขไม่ตรงกัน)
--      - ไม่กรองการ์ดที่จ่ายครบออก: ส่วน 1 และส่วน 3 ต้องใช้การ์ดที่จ่ายครบแล้ว
--        แต่ละ view กรอง is_paid เองตามความหมายของตัวเอง
--    เลือกคอลัมน์เท่าที่ 5 view ข้างล่างใช้ (ไม่ใช้ s.* เพื่อไม่ให้คอลัมน์ใหม่ของ
--    receivable_summary ไหลเข้ามาเองในอนาคต)
-- ---------------------------------------------------------------------------
create view public.stats_cards
with (security_invoker = true)
as
select
  s.id,
  s.company_id,
  s.company_name,
  s.due_month,
  s.account_month,
  s.total_amount,
  s.paid_amount,
  s.balance,
  s.is_paid,
  s.actual_due_date,
  s.days_to_actual_due,
  s.paid_late_actual_days,
  s.created_at
from public.receivable_summary s
where s.company_name not like '[TEST]%';

comment on view public.stats_cards is
  'ฐานร่วมของหน้าสถิติ (schema.md 4.5): การ์ดที่นับในสถิติ = ไม่ถูกยกเลิก และบริษัทไม่ใช่ [TEST] · บริษัทจริงห้ามชื่อขึ้นต้นด้วย [TEST]';

-- ---------------------------------------------------------------------------
-- 2. stats_overview — 1 แถว: ภาพรวม ณ วันนี้ + ขอบเขตของข้อมูล
--    data_since = วันที่ของการ์ดใบแรกสุดในระบบ (เวลาไทย) → บรรทัดบอกข้อจำกัดบนหน้า
--    ("ข้อมูลเริ่มตั้งแต่ … ค่าเฉลี่ยจะแม่นขึ้นเมื่อมีข้อมูลหลายเดือน") ต้องมาจาก database
--    ไม่ใช่ฮาร์ดโค้ดวันที่ไว้ในแอป เพราะเดือนหน้าข้อความจะผิดทันที
--
--    ชั้นนอกไม่ได้อ่านตารางไหน (aggregate คืน 1 แถวเสมอแม้ไม่มีการ์ด) จึงต้องเขียนเงื่อนไข
--    สิทธิ์เองเหมือน report_asof: my_role() เป็น null = ไม่มี profile หรือ is_active = false
--    → ได้ 0 แถว ไม่ใช่แถวที่เป็นเลข 0 ทั้งแถว
-- ---------------------------------------------------------------------------
create view public.stats_overview
with (security_invoker = true)
as
select
  (now() at time zone 'Asia/Bangkok')::date as today,
  a.data_since,
  a.company_count,
  a.card_count,
  a.outstanding_total,
  a.outstanding_card_count,
  a.overdue_total,
  a.overdue_card_count
from (
  select
    min(c.created_at at time zone 'Asia/Bangkok')::date  as data_since,
    count(distinct c.company_id)::int                   as company_count,
    count(*)::int                                       as card_count,
    coalesce(sum(c.balance) filter (where not c.is_paid), 0)::numeric(14,2)
                                                        as outstanding_total,
    (count(*) filter (where not c.is_paid))::int        as outstanding_card_count,
    coalesce(sum(c.balance) filter (where not c.is_paid and c.days_to_actual_due < 0), 0)::numeric(14,2)
                                                        as overdue_total,
    (count(*) filter (where not c.is_paid and c.days_to_actual_due < 0))::int
                                                        as overdue_card_count
  from public.stats_cards c
) a
where (select public.my_role()) is not null;

comment on view public.stats_overview is
  'ภาพรวมหน้าสถิติ 1 แถว (schema.md 4.5): ยอดค้าง / ยอดเลยกำหนด ณ วันนี้ + data_since สำหรับบรรทัดบอกข้อจำกัด · อ่านได้เฉพาะผู้ใช้ที่ใช้งานอยู่';

-- ---------------------------------------------------------------------------
-- 3. stats_collection_by_month — ส่วน 1: "เก็บเงินเดือนนี้ได้กี่ %"
--    เดือน = due_month (เดือนของวันครบกำหนดจริง) **ตัวเดียวกับหน้าสรุปรายเดือน**
--    เพื่อให้ยอด "ต้องได้รับ" ของเดือนเดียวกันตรงกับ monthly_report_total.total_amount_sum เป๊ะ
--
--    ความหมายที่ต้องไม่อ่านผิด: collected_total = "เก็บได้แล้วเท่าไรจากยอดที่ครบกำหนดเดือนนั้น"
--    ไม่ใช่ "เงินที่เข้ามาในเดือนนั้น" (เงินที่จ่ายช้าข้ามเดือนยังนับเข้าเดือนที่ครบกำหนด)
--    → % ของเดือนที่ผ่านมาจะขยับขึ้นได้เรื่อย ๆ เมื่อลูกค้าจ่ายตามหลัง ซึ่งเป็นสิ่งที่ต้องการ
--
--    เดือนที่ไม่มีการ์ดเลย = ไม่มีแถว → แอปแสดงสถานะ "ไม่มีการ์ดในเดือนนี้"
--    ไม่ใช่เขียนเลข 0 ขึ้นมาเอง (กฎเดียวกับ monthly_report_total)
--    due_total > 0 เสมอ (total_amount ต้อง > 0 และมีอย่างน้อย 1 ใบ) แต่ใส่ nullif กันไว้
-- ---------------------------------------------------------------------------
create view public.stats_collection_by_month
with (security_invoker = true)
as
select
  c.due_month,
  count(*)::int                             as card_count,
  (count(*) filter (where c.is_paid))::int  as paid_card_count,
  sum(c.total_amount)::numeric(14,2)        as due_total,
  sum(c.paid_amount)::numeric(14,2)         as collected_total,
  sum(c.balance)::numeric(14,2)             as balance_total,
  trunc(sum(c.paid_amount) / nullif(sum(c.total_amount), 0) * 100, 2)::numeric(5,2)
                                            as collected_pct
from public.stats_cards c
group by c.due_month;

comment on view public.stats_collection_by_month is
  'ส่วน 1 ของหน้าสถิติ (schema.md 4.5): ต่อ 1 เดือนครบกำหนด — ยอดที่ต้องได้รับ / เก็บได้แล้ว / คงเหลือ / % ที่เก็บได้ (trunc 2 ตำแหน่ง)';

-- ---------------------------------------------------------------------------
-- 4. stats_aging — ส่วน 2: อายุหนี้ค้าง ณ วันนี้ (**4 แถวคงที่เสมอ**)
--    นับเฉพาะการ์ดที่ยังจ่ายไม่ครบ · จัดกลุ่มจาก days_to_actual_due ของ receivable_summary
--    (= actual_due_date − วันนี้ตามเวลาไทย · บวก = ยังไม่ถึงกำหนด · ลบ = เลยกำหนดมาแล้ว)
--
--      not_due   days_to_actual_due >= 0      ยังไม่ถึงกำหนด — **รวมใบที่ครบกำหนดวันนี้**
--                                             (ตรงกับการ์ดในหน้าตารางที่ยังไม่ขึ้น "เลยกำหนด")
--      d1_30     −1 ถึง −30                   เลยกำหนด 1–30 วัน
--      d31_60    −31 ถึง −60                  เลยกำหนด 31–60 วัน
--      d60_plus  น้อยกว่า −60                 เลยกำหนดเกิน 60 วัน
--
--    ใช้ values + cross join lateral เพื่อให้ได้ 4 แถวเสมอแม้กลุ่มนั้นไม่มีการ์ด (ยอด 0.00)
--    แอปจะไม่ต้องปั้นแถวที่หายไปขึ้นมาเอง และ bucket_order ทำให้ลำดับบนหน้าจอมาจาก database
--    pct_of_outstanding เทียบกับยอดค้างรวมทั้งหมด = **ความกว้างของแถบ** (แอปไม่ต้องบวก 4 แถว)
--    ชื่อกลุ่มเป็นรหัส (not_due / d1_30 / …) ไม่ใช่ข้อความไทย เพราะหน้าจอมี 2 ภาษา
--    ไม่มียอดค้างเลย → ทั้ง 4 แถวเป็น 0.00 / 0 ใบ / 0.00% (แอปแสดงสถานะว่างจาก outstanding_total)
-- ---------------------------------------------------------------------------
create view public.stats_aging
with (security_invoker = true)
as
select
  b.bucket,
  b.bucket_order,
  x.balance_total,
  x.card_count,
  coalesce(trunc(x.balance_total / nullif(tot.outstanding_total, 0) * 100, 2), 0)::numeric(5,2)
    as pct_of_outstanding
from (values
  ('not_due', 1),
  ('d1_30', 2),
  ('d31_60', 3),
  ('d60_plus', 4)
) as b(bucket, bucket_order)
cross join lateral (
  select coalesce(sum(c.balance), 0)::numeric(14,2) as balance_total,
         count(*)::int                              as card_count
  from public.stats_cards c
  where not c.is_paid
    and case b.bucket
          when 'not_due' then c.days_to_actual_due >= 0
          when 'd1_30'   then c.days_to_actual_due between -30 and -1
          when 'd31_60'  then c.days_to_actual_due between -60 and -31
          else                c.days_to_actual_due < -60
        end
) x
cross join lateral (
  select coalesce(sum(c2.balance), 0)::numeric(14,2) as outstanding_total
  from public.stats_cards c2
  where not c2.is_paid
) tot
-- 4 แถวนี้มาจาก values ไม่ได้มาจากตาราง → RLS ไม่ได้กรองให้ ต้องเขียนเงื่อนไขสิทธิ์เอง
-- เหมือน report_asof / stats_overview ไม่งั้น anon ที่หลุด grant มาได้ หรือบัญชีที่ปิดแล้ว
-- จะได้ 4 แถวที่เป็นเลข 0 ทั้งแถว (ไม่ใช่ข้อมูลรั่ว แต่ควรได้ 0 แถวให้เหมือนกันทุก view)
where (select public.my_role()) is not null;

comment on view public.stats_aging is
  'ส่วน 2 ของหน้าสถิติ (schema.md 4.5): ยอดค้าง ณ วันนี้แยก 4 กลุ่มอายุหนี้ (4 แถวเสมอ) + สัดส่วนสำหรับความกว้างแถบ · not_due รวมใบที่ครบกำหนดวันนี้';

-- ---------------------------------------------------------------------------
-- 5. stats_company_behavior — ส่วน 3: พฤติกรรมการจ่ายของลูกค้าแต่ละบริษัท
--    1 แถวต่อ 1 บริษัทที่มีการ์ดอยู่ในสถิติ (บริษัทที่ยังไม่มีการ์ดเลยไม่โผล่)
--
--    ตรงเวลา = paid_late_actual_days <= 0 (จ่ายครบก่อนหรือตรงวันครบกำหนดจริง)
--    avg_late_days = ค่าเฉลี่ยของ greatest(paid_late_actual_days, 0) เฉพาะการ์ดที่จ่ายครบ
--      **ตัดค่าติดลบเป็น 0 ก่อนเฉลี่ย** (ลูกค้ายืนยัน 20 ต.ค.): ถ้าใช้ค่าดิบ การจ่ายก่อนกำหนด
--      10 วันจะไปหักกับการจ่ายช้า 10 วัน แล้วบริษัทที่จ่ายเร็วบ้างช้าบ้างจะดูเหมือน "ตรงเวลา"
--      ตัวเลขนี้ตอบคำถาม "เวลาช้า ช้าประมาณกี่วัน" ไม่ใช่ "เร็วหรือช้าโดยรวม"
--      ยังไม่มีการ์ดจ่ายครบ → ว่าง (null) ไม่ใช่ 0 เพื่อไม่ให้อ่านว่า "ตรงเวลาเป๊ะ"
--    max_late_days ตัดเป็น 0 ด้วยเหตุผลเดียวกัน (0 = ไม่เคยช้า)
--    is_thin = การ์ดที่จ่ายครบน้อยกว่า 2 ใบ → หน้าจอติดป้าย "ข้อมูลยังน้อย"
--
--    seq = ลำดับที่หน้าจอต้องเรียง (ลำดับมาจาก database แอปไม่เรียงเอง):
--      ช้าสุดอยู่บน แต่ **ดันบริษัทที่ข้อมูลยังน้อยไปท้ายสุด** เพราะการ์ด 1 ใบที่ช้า 30 วัน
--      ไม่ควรขึ้นอันดับ 1 เหนือบริษัทที่มี 10 ใบและช้าเฉลี่ย 20 วัน
--      เสมอกัน → การ์ดที่เลยกำหนดอยู่ตอนนี้มากกว่าอยู่บน แล้วตัดด้วยชื่อบริษัทให้ลำดับคงที่
-- ---------------------------------------------------------------------------
create view public.stats_company_behavior
with (security_invoker = true)
as
select
  row_number() over (
    order by a.is_thin,
             a.avg_late_days desc nulls last,
             a.overdue_now_count desc,
             a.company_name
  )::int as seq,
  a.company_id,
  a.company_name,
  a.card_count,
  a.paid_card_count,
  a.on_time_count,
  a.late_card_count,
  a.on_time_pct,
  a.avg_late_days,
  a.max_late_days,
  a.overdue_now_count,
  a.overdue_now_total,
  a.open_card_count,
  a.open_total,
  a.is_thin
from (
  select
    c.company_id,
    c.company_name,
    count(*)::int                                                    as card_count,
    (count(*) filter (where c.is_paid))::int                         as paid_card_count,
    (count(*) filter (where c.is_paid and c.paid_late_actual_days <= 0))::int
                                                                     as on_time_count,
    (count(*) filter (where c.is_paid and c.paid_late_actual_days > 0))::int
                                                                     as late_card_count,
    trunc(
      (count(*) filter (where c.is_paid and c.paid_late_actual_days <= 0))::numeric
      / nullif((count(*) filter (where c.is_paid)), 0) * 100, 2
    )::numeric(5,2)                                                  as on_time_pct,
    round(
      (avg(greatest(c.paid_late_actual_days, 0)) filter (where c.is_paid)), 1
    )::numeric(6,1)                                                  as avg_late_days,
    (max(greatest(c.paid_late_actual_days, 0)) filter (where c.is_paid))::int
                                                                     as max_late_days,
    (count(*) filter (where not c.is_paid and c.days_to_actual_due < 0))::int
                                                                     as overdue_now_count,
    coalesce(sum(c.balance) filter (where not c.is_paid and c.days_to_actual_due < 0), 0)::numeric(14,2)
                                                                     as overdue_now_total,
    (count(*) filter (where not c.is_paid))::int                     as open_card_count,
    coalesce(sum(c.balance) filter (where not c.is_paid), 0)::numeric(14,2)
                                                                     as open_total,
    (count(*) filter (where c.is_paid)) < 2                          as is_thin
  from public.stats_cards c
  group by c.company_id, c.company_name
) a;

comment on view public.stats_company_behavior is
  'ส่วน 3 ของหน้าสถิติ (schema.md 4.5): พฤติกรรมการจ่ายต่อบริษัท — จ่ายครบกี่ใบ / ตรงเวลา % / ช้าเฉลี่ยกี่วัน (ตัดค่าติดลบเป็น 0) / เลยกำหนดอยู่ตอนนี้ · seq เรียงช้าสุดก่อน และดัน is_thin ไปท้าย';

-- ---------------------------------------------------------------------------
-- 6. stats_company_balance — ส่วน 4: "ยอดค้างกระจุกที่ใคร"
--    1 แถวต่อ 1 บริษัทที่ยังมียอดค้าง เรียงมาก → น้อย (seq = 1 คือสูงสุด)
--    **ส่งมาทุกบริษัท ไม่ limit 5 ที่นี่** (ลูกค้ายืนยัน 20 ต.ค.): แอปแสดง seq <= 5
--    อยากเปลี่ยนเป็น 10 ทีหลังจะไม่ต้องเขียน migration ใหม่ และการเลือกแสดง 5 แถวแรก
--    ไม่ใช่การคำนวณเงิน
--
--    pct_of_outstanding = สัดส่วนของบริษัทนั้นต่อยอดค้างทั้งหมด (ความกว้างแถบ)
--    cum_pct            = สัดส่วนสะสมจากอันดับ 1 ถึงแถวนี้
--      → ประโยค "5 อันดับนี้รวมกัน X% ของยอดค้างทั้งหมด" อ่าน cum_pct ของแถว seq = 5
--        (หรือแถวสุดท้ายถ้ามีน้อยกว่า 5 บริษัท) แอปไม่ต้องบวก % เอง
--      window ทั้งคู่คำนวณก่อน limit ของแอป จึงเทียบกับยอดค้าง "ทั้งหมด" จริง
--      frame เขียน rows ชัด ๆ กันกรณียอดค้างเท่ากันแล้ว default range จะรวมแถวที่เสมอกันเข้ามา
-- ---------------------------------------------------------------------------
create view public.stats_company_balance
with (security_invoker = true)
as
select
  row_number() over (order by a.balance_total desc, a.company_name)::int as seq,
  a.company_id,
  a.company_name,
  a.balance_total,
  a.open_card_count,
  a.overdue_card_count,
  coalesce(trunc(a.balance_total / nullif(sum(a.balance_total) over (), 0) * 100, 2), 0)::numeric(5,2)
    as pct_of_outstanding,
  coalesce(trunc(
    sum(a.balance_total) over (
      order by a.balance_total desc, a.company_name
      rows between unbounded preceding and current row
    ) / nullif(sum(a.balance_total) over (), 0) * 100, 2), 0)::numeric(5,2)
    as cum_pct
from (
  select
    c.company_id,
    c.company_name,
    sum(c.balance)::numeric(14,2)                            as balance_total,
    count(*)::int                                            as open_card_count,
    (count(*) filter (where c.days_to_actual_due < 0))::int    as overdue_card_count
  from public.stats_cards c
  where not c.is_paid
  group by c.company_id, c.company_name
) a;

comment on view public.stats_company_balance is
  'ส่วน 4 ของหน้าสถิติ (schema.md 4.5): ยอดค้างต่อบริษัท เรียงมาก → น้อย + % ของยอดค้างทั้งหมด และ % สะสม (cum_pct) · ส่งทุกบริษัท แอปแสดง 5 อันดับแรก';

-- ---------------------------------------------------------------------------
-- 7. สิทธิ์: อ่านได้ทั้ง owner และ sales · ไม่มีใครเขียนได้ · anon ไม่ได้อะไรเลย
--    stats_cards ต้องอยู่ในรายการด้วย เพราะ security_invoker ตรวจสิทธิ์ของคนที่อ่านทุกชั้น
-- ---------------------------------------------------------------------------
revoke all on table
  public.stats_cards,
  public.stats_overview,
  public.stats_collection_by_month,
  public.stats_aging,
  public.stats_company_behavior,
  public.stats_company_balance
  from anon, authenticated;

grant select on table
  public.stats_cards,
  public.stats_overview,
  public.stats_collection_by_month,
  public.stats_aging,
  public.stats_company_behavior,
  public.stats_company_balance
  to authenticated;

-- ตรวจผลเบื้องต้น: ต้องได้ PASS ทุกช่องของทั้ง 6 view
-- (ชุดตรวจเต็มรวมตัวเลขและการจัดกลุ่มอยู่ใน supabase/tests/stats_checks.sql)
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
from (values
  ('stats_cards'),
  ('stats_overview'),
  ('stats_collection_by_month'),
  ('stats_aging'),
  ('stats_company_behavior'),
  ('stats_company_balance')
) as x(viewname)
join pg_class c on c.oid = ('public.' || x.viewname)::regclass
order by x.viewname;
