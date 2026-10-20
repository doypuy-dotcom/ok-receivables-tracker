-- stats_checks.sql — ตรวจ 6 view ของหน้าสถิติ (/stats) แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 008_stats_views.sql)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบและทุกการเขียนที่ทดลองถูก rollback เสมอ
-- **ผลทุกข้อออกมาใน result set เดียวที่ท้ายไฟล์** (SQL Editor แสดงเฉพาะชุดสุดท้าย):
--   ข้อ 0 = แถวสรุป "PASS x / y ข้อ" + ALL PASS หรือ HAS FAIL · ข้อ 1–56 = ผลแต่ละข้อ
--   ผลที่ถูกต้องคือ **ALL PASS 71 / 71** (71 แถว ไม่ใช่ 56 เพราะข้อ 53–55 ออก 6 แถวต่อข้อ
--   = 1 แถวต่อ 1 view เหมือน v2_checks ที่ 28 ข้อออก 34 แถว)
--
-- -------------------------------------------------------------------------------------
-- ชื่อข้อมูลทดสอบ 2 ชุด — จำเป็น เพราะกฎของหน้าสถิติชนกับกฎข้อมูลทดสอบของโปรเจกต์
--   stats_cards กรอง company_name like '[TEST]%' ออก (AGENTS.md: ข้อมูลทดสอบ/เดโมต้องใช้ [TEST])
--   → ถ้าใช้ชื่อ [TEST] ทั้งไฟล์ จะ "ตรวจตัวเลข" ไม่ได้เลย เพราะทุกแถวถูกกรองออกก่อน
--   จึงแยกเป็น 2 ชุด:
--     [TEST] stats <เวลา>      → ใช้พิสูจน์ว่า **ถูกกรองออกจริง** (ข้อ 26–30)
--     ZZ-STATS-CHECK <เวลา>    → ใช้พิสูจน์ **ตัวเลข** (ไม่มี prefix [TEST] จึงถูกนับ)
--   ทั้ง 2 ชุดอยู่ใน block ที่ rollback เสมอ และ **ข้อ 56 ตรวจหลัง rollback ว่าไม่มีอะไรค้าง**
--   ถ้าข้อ 56 FAIL (เช่นรันค้างกลางทางด้วยวิธีอื่น) ให้เก็บกวาดด้วย:
--     select id, name from public.companies where name like 'ZZ-STATS-CHECK%';
--     -- การ์ด/การจ่ายของบริษัทนั้นต้อง is_cancelled = true (ห้าม delete — ห้ามลบแถวในโปรเจกต์นี้)
--   กฎที่ตามมาและเขียนไว้ใน AGENTS.md แล้ว: **บริษัทจริงห้ามชื่อขึ้นต้นด้วย [TEST]**
-- -------------------------------------------------------------------------------------
-- ข้อมูลทดสอบชุด ZZ (T = วันนี้ตามเวลาไทย · MF = อีก 13 เดือน · MF1 = อีก 14 เดือน):
--   a  3 ใบจ่ายครบ ช้า 10 / 20 / 30 วัน (1,000 ต่อใบ) + 1 ใบค้าง 5,000 ครบกำหนด T−5
--      → จ่ายครบ 3 ใบ · ตรงเวลา 0% · ช้าเฉลี่ย 20.0 · ช้าสุด 30 · เลยกำหนดอยู่ 1 ใบ
--   b  2 ใบจ่ายครบ ช้า −5 และ 0 วัน (1,000 ต่อใบ) ไม่มีใบค้าง
--      → ตรงเวลา 100% · ช้าเฉลี่ย 0.0 (ค่าติดลบถูกตัดเป็น 0 ก่อนเฉลี่ย ไม่หักกับใบอื่น)
--   c  1 ใบจ่ายครบ ช้า 40 วัน → ช้าที่สุดในชุด แต่ is_thin = true จึงต้องถูกดันไปท้ายตาราง
--   d  1 ใบค้าง 7,000 ครบกำหนด T−5 ไม่มีใบจ่ายครบเลย → on_time_pct / avg_late_days เป็น null
--   e  6 ใบค้าง วางที่ "ขอบ" ของทุกกลุ่มอายุหนี้พอดี (ใช้ตรวจการจัดกลุ่มข้อ 3–6):
--        T+0 = 100 (ครบกำหนดวันนี้ → ยังไม่ถึงกำหนด) · T−1 = 200 · T−30 = 400
--        T−31 = 800 · T−60 = 1,600 · T−61 = 3,200
--   f  1 ใบในเดือน MF: 10,000 จ่าย 1,234.56 → % ที่เก็บได้ = 12.3456 → ต้องได้ 12.34 (trunc ไม่ปัด)
--   g  2 ใบในเดือน MF1: 8,000 จ่ายครบ + 2,000 ยังค้าง → จ่ายครบแล้วยังอยู่ในเดือนนั้น
--   h  1 ใบ 3,000 ใช้ทดสอบว่า "ยกเลิกการ์ดแล้วยอดกลับเท่าเดิมเป๊ะ" (ข้อ 31)
--
-- วิธีตรวจตัวเลขทั้งที่ฐานข้อมูลมีข้อมูลลูกค้าจริงอยู่:
--   - ส่วนที่แยกตามบริษัท (ข้อ 13–21) กรองด้วยชื่อชุด ZZ ได้ตรง ๆ → เทียบค่าเป๊ะ
--   - ส่วนที่รวมทั้งระบบ (อายุหนี้ / ภาพรวม ข้อ 3–11) ใช้วิธี **วัดส่วนต่าง**:
--     ถ่ายค่าก่อนเพิ่มข้อมูล (S0) → เพิ่ม → ถ่ายอีกครั้ง (S1) → ส่วนต่างต้องเท่ากับของชุด ZZ พอดี
--   - ส่วนที่แยกตามเดือน (ข้อ 22–25) ใช้เดือน MF / MF1 ที่ไม่มีการ์ดจริงปน (มีข้อตรวจกำกับไว้)

create temp table if not exists stats_results (n int, test text, result text);
truncate stats_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today constant date := (now() at time zone 'Asia/Bangkok')::date;
  m0    constant date := date_trunc('month', (now() at time zone 'Asia/Bangkok'))::date;
  mf    constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '13 months')::date;
  mf1   constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '14 months')::date;
  mf2   constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '15 months')::date;
  stamp constant text := to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  tag_z constant text := 'ZZ-STATS-CHECK ' || stamp;   -- ถูกนับในสถิติ (ใช้ตรวจตัวเลข)
  tag_t constant text := '[TEST] stats ' || stamp;     -- ต้องถูกกรองออกจากสถิติ
  owner_claims text;
  sales_claims text;
  comp_a uuid; comp_b uuid; comp_c uuid; comp_d uuid; comp_e uuid;
  comp_f uuid; comp_g uuid; comp_h uuid; comp_t uuid;
  card_x uuid; card_h uuid;
  -- ภาพถ่ายค่าก่อน/หลัง (jsonb เทียบทั้งแถวได้ในครั้งเดียว)
  s0_aging jsonb; s1_aging jsonb; s2_aging jsonb; s3_aging jsonb;
  s0_ov    jsonb; s1_ov    jsonb; s2_ov    jsonb; s3_ov    jsonb; ow_ov jsonb;
  s2_coll  jsonb; s3_coll  jsonb;
  res text[] := '{}';
  v record;
  w record;
  r2 record;
  outcome text;
  note text;
  txt text;
  expected text;
  n_rows int;
  n_bad int;
  n_cards0 int;
  n_cards1 int;
  d_amt numeric;
  d_amt2 numeric;
  d_cnt int;
  pct_sum numeric;
  exp_pct numeric;
  all_denied boolean;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;
  owner_claims := json_build_object('sub', owner_id, 'role', 'authenticated')::text;
  sales_claims := json_build_object('sub', sales_id, 'role', 'authenticated')::text;

  begin  -- ทุกอย่างใน block นี้ถูก rollback ตอนจบ (raise 'stats_undo')

    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;

    -- -----------------------------------------------------------------------
    -- S0: ถ่ายค่าก่อนเพิ่มข้อมูลทดสอบ (ใช้วัดส่วนต่างในข้อ 3–11)
    -- -----------------------------------------------------------------------
    select jsonb_object_agg(g.bucket, jsonb_build_array(g.balance_total, g.card_count))
      into s0_aging from public.stats_aging g;
    select to_jsonb(o) into s0_ov from public.stats_overview o;
    select count(*) into n_cards0 from public.stats_cards;

    -- -----------------------------------------------------------------------
    -- เตรียมข้อมูล (เขียนในนามบัญชี sales ผ่าน RLS + trigger จริง)
    -- -----------------------------------------------------------------------
    insert into public.companies (name) values (tag_z || ' a') returning id into comp_a;
    insert into public.companies (name) values (tag_z || ' b') returning id into comp_b;
    insert into public.companies (name) values (tag_z || ' c') returning id into comp_c;
    insert into public.companies (name) values (tag_z || ' d') returning id into comp_d;
    insert into public.companies (name) values (tag_z || ' e') returning id into comp_e;

    -- a: 3 ใบจ่ายครบ ช้า 10 / 20 / 30 วัน (บริษัทเดียวกันต้องต่าง account_month กัน)
    for v in select * from (values (1, 50, 40), (2, 60, 40), (3, 70, 40)) q(k, due_ago, paid_ago)
    loop
      insert into public.receivables
        (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
      values
        (comp_a, (m0 - (v.k || ' months')::interval)::date, 1000, 30,
         today - v.due_ago - 30, today - v.due_ago - 30, today - v.due_ago)
      returning id into card_x;
      insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
      values (card_x, 1000, 'transfer', today - v.paid_ago, '10:00');
    end loop;
    -- a: อีก 1 ใบยังค้าง 5,000 เลยกำหนด 5 วัน (กลุ่ม d1_30)
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, (m0 - interval '4 months')::date, 5000, 30, today - 35, today - 35, today - 5);

    -- b: 2 ใบจ่ายครบ ช้า −5 (จ่ายก่อนกำหนด) และ 0 วัน (ตรงวัน)
    for v in select * from (values (1, 20, 25), (2, 30, 30)) q(k, due_ago, paid_ago)
    loop
      insert into public.receivables
        (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
      values
        (comp_b, (m0 - (v.k || ' months')::interval)::date, 1000, 30,
         today - v.due_ago - 30, today - v.due_ago - 30, today - v.due_ago)
      returning id into card_x;
      insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
      values (card_x, 1000, 'transfer', today - v.paid_ago, '11:00');
    end loop;

    -- c: 1 ใบจ่ายครบ ช้า 40 วัน (ช้าสุดในชุด แต่มีการ์ดจ่ายครบใบเดียว → ข้อมูลยังน้อย)
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_c, (m0 - interval '1 month')::date, 1000, 30, today - 130, today - 130, today - 100)
    returning id into card_x;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_x, 1000, 'transfer', today - 60, '12:00');

    -- d: ไม่มีใบจ่ายครบเลย มีแต่ใบค้าง 7,000 เลยกำหนด 5 วัน
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_d, (m0 - interval '1 month')::date, 7000, 30, today - 35, today - 35, today - 5);

    -- e: 6 ใบค้าง วางที่ขอบของทุกกลุ่มอายุหนี้พอดี
    for v in select * from (values
        (1, 0, 100), (2, -1, 200), (3, -30, 400), (4, -31, 800), (5, -60, 1600), (6, -61, 3200)
      ) q(k, off, amt)
    loop
      insert into public.receivables
        (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
      values
        (comp_e, (m0 - (v.k || ' months')::interval)::date, v.amt, 30,
         today + v.off - 30, today + v.off - 30, today + v.off);
    end loop;

    -- -----------------------------------------------------------------------
    -- S1: ถ่ายค่าหลังเพิ่ม a–e (14 ใบ: จ่ายครบ 6 · ยังค้าง 8)
    -- -----------------------------------------------------------------------
    select jsonb_object_agg(g.bucket, jsonb_build_array(g.balance_total, g.card_count))
      into s1_aging from public.stats_aging g;
    select to_jsonb(o) into s1_ov from public.stats_overview o;
    select count(*) into n_cards1 from public.stats_cards;

    -- -----------------------------------------------------------------------
    -- 1: อ่านได้ทั้ง 6 view (และ stats_cards เห็นการ์ดทดสอบครบ 14 ใบ)
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.stats_cards where company_name like tag_z || '%';
    res := res || array['1', 'sales: อ่านทั้ง 6 view ได้ · stats_cards เห็นการ์ดทดสอบ 14 ใบ',
      case when n_rows = 14 and n_cards1 - n_cards0 = 14 then 'PASS'
           else format('FAIL (เห็น %s ใบ / ส่วนต่างทั้งระบบ %s ใบ)', n_rows, n_cards1 - n_cards0) end];

    -- -----------------------------------------------------------------------
    -- 2: stats_aging ได้ 4 แถวเสมอ และลำดับกลุ่มมาจาก database (bucket_order 1–4)
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.stats_aging;
    select string_agg(g.bucket, ',' order by g.bucket_order) into txt from public.stats_aging g;
    res := res || array['2', 'stats_aging: 4 แถวเสมอ เรียงตาม bucket_order = not_due, d1_30, d31_60, d60_plus',
      case when n_rows = 4 and txt = 'not_due,d1_30,d31_60,d60_plus' then 'PASS'
           else format('FAIL (%s แถว: %s)', n_rows, coalesce(txt, 'ไม่มีแถว')) end];

    -- -----------------------------------------------------------------------
    -- 3–6: การจัดกลุ่มอายุหนี้ ตรวจที่ "ขอบ" ของทุกกลุ่มด้วยส่วนต่าง S1 − S0
    --      0 → ยังไม่ถึงกำหนด · −1 และ −30 → 1–30 วัน · −31 และ −60 → 31–60 วัน · −61 → เกิน 60
    --      ใบที่เลยกำหนด 5 วันของ a (5,000) และ d (7,000) ก็อยู่กลุ่ม d1_30 ด้วย
    -- -----------------------------------------------------------------------
    for v in select * from (values
        (3, 'not_due',  'ยังไม่ถึงกำหนด (รวมใบที่ครบกำหนดวันนี้ = 0 วัน)',     100.00, 1),
        (4, 'd1_30',    'เลยกำหนด 1–30 วัน (ขอบ −1 และ −30 · รวม a และ d)', 12600.00, 4),
        (5, 'd31_60',   'เลยกำหนด 31–60 วัน (ขอบ −31 และ −60)',              2400.00, 2),
        (6, 'd60_plus', 'เลยกำหนดเกิน 60 วัน (ขอบ −61)',                     3200.00, 1)
      ) q(n, bucket, label, exp_amt, exp_cnt)
    loop
      d_amt := (s1_aging -> v.bucket ->> 0)::numeric - (s0_aging -> v.bucket ->> 0)::numeric;
      d_cnt := (s1_aging -> v.bucket ->> 1)::int     - (s0_aging -> v.bucket ->> 1)::int;
      res := res || array[v.n::text,
        format('กลุ่ม %s: %s → ต้องเพิ่ม %s / %s ใบ', v.bucket, v.label, v.exp_amt, v.exp_cnt),
        case when d_amt = v.exp_amt and d_cnt = v.exp_cnt then 'PASS'
             else format('FAIL (เพิ่ม %s / %s ใบ)', d_amt, d_cnt) end];
    end loop;

    -- -----------------------------------------------------------------------
    -- 7: การ์ดที่จ่ายครบแล้วไม่ถูกนับในอายุหนี้
    --    เพิ่ม 14 ใบ (จ่ายครบ 6) → 4 กลุ่มรวมกันต้องเพิ่มแค่ 8 ใบ
    -- -----------------------------------------------------------------------
    d_cnt := 0;
    for v in select * from (values ('not_due'), ('d1_30'), ('d31_60'), ('d60_plus')) q(bucket)
    loop
      d_cnt := d_cnt + (s1_aging -> v.bucket ->> 1)::int - (s0_aging -> v.bucket ->> 1)::int;
    end loop;
    res := res || array['7', 'อายุหนี้ไม่นับการ์ดที่จ่ายครบ: เพิ่ม 14 ใบ (จ่ายครบ 6) → 4 กลุ่มเพิ่มรวม 8 ใบ',
      case when d_cnt = 8 then 'PASS' else format('FAIL (เพิ่มรวม %s ใบ)', d_cnt) end];

    -- -----------------------------------------------------------------------
    -- 8: ผลรวม 4 กลุ่ม = ยอดค้างทั้งหมดของ stats_overview (ตัวเลข 2 ที่ต้องตรงกัน)
    -- -----------------------------------------------------------------------
    select sum(g.balance_total), sum(g.card_count) into d_amt, d_cnt from public.stats_aging g;
    res := res || array['8', 'ผลรวม 4 กลุ่มอายุหนี้ = outstanding_total / outstanding_card_count ของ stats_overview',
      case when d_amt = (s1_ov ->> 'outstanding_total')::numeric
            and d_cnt = (s1_ov ->> 'outstanding_card_count')::int then 'PASS'
           else format('FAIL (อายุหนี้ %s / %s ใบ · ภาพรวม %s / %s ใบ)',
                       d_amt, d_cnt, s1_ov ->> 'outstanding_total', s1_ov ->> 'outstanding_card_count') end];

    -- -----------------------------------------------------------------------
    -- 9: สัดส่วนของ 4 กลุ่มรวมกันได้ 100% (ขาดได้ไม่เกิน 0.04 จากการ trunc 4 แถว)
    --    = ความกว้างแถบมาจาก database จริง ไม่ต้องให้แอปบวกเอง
    -- -----------------------------------------------------------------------
    select sum(g.pct_of_outstanding) into pct_sum from public.stats_aging g;
    res := res || array['9', 'สัดส่วน 4 กลุ่มรวมกัน = 100% (± 0.04 จากการตัดทศนิยม)',
      case when (s1_ov ->> 'outstanding_total')::numeric = 0 and pct_sum = 0 then 'PASS (ไม่มียอดค้าง)'
           when pct_sum between 99.96 and 100.00 then 'PASS (' || pct_sum || '%)'
           else format('FAIL (รวม %s%%)', pct_sum) end];

    -- -----------------------------------------------------------------------
    -- 10–11: stats_overview — ยอดค้างและยอดเลยกำหนด เพิ่มขึ้นเท่าชุดทดสอบพอดี
    --    ยอดค้าง   5,000 + 7,000 + 6,300 = 18,300 (8 ใบ)
    --    เลยกำหนด  18,300 − 100 (ใบที่ครบกำหนดวันนี้) = 18,200 (7 ใบ)
    -- -----------------------------------------------------------------------
    res := res || array['10', 'stats_overview: ยอดค้างเพิ่ม 18,300.00 / 8 ใบ',
      case when (s1_ov ->> 'outstanding_total')::numeric - (s0_ov ->> 'outstanding_total')::numeric = 18300.00
            and (s1_ov ->> 'outstanding_card_count')::int - (s0_ov ->> 'outstanding_card_count')::int = 8
           then 'PASS'
           else format('FAIL (เพิ่ม %s / %s ใบ)',
                       (s1_ov ->> 'outstanding_total')::numeric - (s0_ov ->> 'outstanding_total')::numeric,
                       (s1_ov ->> 'outstanding_card_count')::int - (s0_ov ->> 'outstanding_card_count')::int) end];

    res := res || array['11', 'stats_overview: ยอดเลยกำหนดเพิ่ม 18,200.00 / 7 ใบ (ใบที่ครบกำหนดวันนี้ยังไม่นับว่าเลย)',
      case when (s1_ov ->> 'overdue_total')::numeric - (s0_ov ->> 'overdue_total')::numeric = 18200.00
            and (s1_ov ->> 'overdue_card_count')::int - (s0_ov ->> 'overdue_card_count')::int = 7
           then 'PASS'
           else format('FAIL (เพิ่ม %s / %s ใบ)',
                       (s1_ov ->> 'overdue_total')::numeric - (s0_ov ->> 'overdue_total')::numeric,
                       (s1_ov ->> 'overdue_card_count')::int - (s0_ov ->> 'overdue_card_count')::int) end];

    -- -----------------------------------------------------------------------
    -- 12: today / data_since — บรรทัดบอกข้อจำกัดบนหน้าต้องมาจาก database
    --     today = วันนี้ตามเวลาไทย · data_since = วันที่การ์ดใบแรกสุด ไม่ว่างและไม่เกินวันนี้
    -- -----------------------------------------------------------------------
    res := res || array['12', 'stats_overview: today = วันนี้ (เวลาไทย) · data_since มีค่าและไม่เกินวันนี้',
      case when (s1_ov ->> 'today')::date = today
            and (s1_ov ->> 'data_since') is not null
            and (s1_ov ->> 'data_since')::date <= today
           then 'PASS (ข้อมูลเริ่ม ' || (s1_ov ->> 'data_since') || ')'
           else format('FAIL (today=%s, data_since=%s)', s1_ov ->> 'today', s1_ov ->> 'data_since') end];

    -- -----------------------------------------------------------------------
    -- 13–16: stats_company_behavior — ค่าต่อบริษัท เทียบเป๊ะ
    -- -----------------------------------------------------------------------
    select * into v from public.stats_company_behavior where company_name = tag_z || ' a';
    res := res || array['13', 'พฤติกรรม a: จ่ายครบ 3 ใบ · ตรงเวลา 0 ใบ (0.00%) · ช้าเฉลี่ย 20.0 · ช้าสุด 30 · เลยกำหนดอยู่ 1 ใบ 5,000.00 · ไม่ใช่ข้อมูลน้อย',
      case when v.paid_card_count = 3 and v.on_time_count = 0 and v.late_card_count = 3
            and v.on_time_pct = 0.00 and v.avg_late_days = 20.0 and v.max_late_days = 30
            and v.overdue_now_count = 1 and v.overdue_now_total = 5000.00
            and v.open_card_count = 1 and v.open_total = 5000.00 and not v.is_thin
           then 'PASS'
           else format('FAIL (จ่ายครบ %s · ตรงเวลา %s (%s%%) · เฉลี่ย %s · สูงสุด %s · เลยกำหนด %s ใบ %s · thin %s)',
                       v.paid_card_count, v.on_time_count, v.on_time_pct, v.avg_late_days,
                       v.max_late_days, v.overdue_now_count, v.overdue_now_total, v.is_thin) end];

    select * into v from public.stats_company_behavior where company_name = tag_z || ' b';
    res := res || array['14', 'พฤติกรรม b: ตรงเวลา 2/2 (100.00%) · ช้าเฉลี่ย 0.0 — **จ่ายก่อนกำหนด 5 วันถูกตัดเป็น 0 ไม่หักกับใบอื่น** · ไม่มีใบค้าง',
      case when v.paid_card_count = 2 and v.on_time_count = 2 and v.late_card_count = 0
            and v.on_time_pct = 100.00 and v.avg_late_days = 0.0 and v.max_late_days = 0
            and v.open_card_count = 0 and v.open_total = 0.00 and v.overdue_now_count = 0
            and not v.is_thin
           then 'PASS'
           else format('FAIL (จ่ายครบ %s · ตรงเวลา %s (%s%%) · เฉลี่ย %s · สูงสุด %s · ค้าง %s ใบ)',
                       v.paid_card_count, v.on_time_count, v.on_time_pct, v.avg_late_days,
                       v.max_late_days, v.open_card_count) end];

    select * into v from public.stats_company_behavior where company_name = tag_z || ' c';
    res := res || array['15', 'พฤติกรรม c: จ่ายครบ 1 ใบ ช้า 40 วัน → is_thin = true (ป้าย "ข้อมูลยังน้อย" ที่ < 2 ใบ)',
      case when v.paid_card_count = 1 and v.avg_late_days = 40.0 and v.on_time_pct = 0.00
            and v.is_thin
           then 'PASS'
           else format('FAIL (จ่ายครบ %s · เฉลี่ย %s · ตรงเวลา %s%% · thin %s)',
                       v.paid_card_count, v.avg_late_days, v.on_time_pct, v.is_thin) end];

    select * into v from public.stats_company_behavior where company_name = tag_z || ' d';
    res := res || array['16', 'พฤติกรรม d: ยังไม่มีใบจ่ายครบ → on_time_pct และ avg_late_days เป็นค่าว่าง (ไม่ใช่ 0 ที่อ่านว่า "ตรงเวลาเป๊ะ") · เลยกำหนดอยู่ 1 ใบ 7,000.00',
      case when v.paid_card_count = 0 and v.on_time_pct is null and v.avg_late_days is null
            and v.max_late_days is null and v.is_thin
            and v.overdue_now_count = 1 and v.overdue_now_total = 7000.00
           then 'PASS'
           else format('FAIL (จ่ายครบ %s · ตรงเวลา %s · เฉลี่ย %s · สูงสุด %s · เลยกำหนด %s ใบ %s)',
                       v.paid_card_count, v.on_time_pct, v.avg_late_days, v.max_late_days,
                       v.overdue_now_count, v.overdue_now_total) end];

    -- -----------------------------------------------------------------------
    -- 17: seq ของ stats_company_behavior = ลำดับที่หน้าจอต้องเรียง (ลำดับมาจาก database)
    --     ช้าสุดก่อน: a (20.0) → b (0.0) · แล้วบริษัทที่ข้อมูลยังน้อยไปท้าย:
    --     c (40.0 แต่ 1 ใบ) → e (ไม่มีค่าเฉลี่ย เลยกำหนด 5 ใบ) → d (ไม่มีค่าเฉลี่ย เลยกำหนด 1 ใบ)
    -- -----------------------------------------------------------------------
    select string_agg(right(b.company_name, 1), ',' order by b.seq) into txt
    from public.stats_company_behavior b where b.company_name like tag_z || '%';
    res := res || array['17', 'ลำดับพฤติกรรม: ช้าสุดก่อน และดันบริษัทที่ข้อมูลยังน้อยไปท้าย → a, b, c, e, d',
      case when txt = 'a,b,c,e,d' then 'PASS (a, b, c, e, d)'
           else format('FAIL (%s)', coalesce(txt, 'ไม่มีแถว')) end];

    -- -----------------------------------------------------------------------
    -- 18–21: stats_company_balance — ยอดค้างกระจุกที่ใคร
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.stats_company_balance where company_name like tag_z || '%';
    select count(*) into n_bad  from public.stats_company_balance
     where company_name in (tag_z || ' b', tag_z || ' c');
    select string_agg(b.company_name || '=' || b.balance_total, ' | ' order by b.seq) into txt
    from public.stats_company_balance b where b.company_name like tag_z || '%';
    expected := format('%s d=7000.00 | %s e=6300.00 | %s a=5000.00', tag_z, tag_z, tag_z);
    res := res || array['18', 'ยอดค้างต่อบริษัท: d 7,000 · e 6,300 · a 5,000 · บริษัทที่จ่ายครบหมด (b, c) ไม่โผล่',
      case when n_bad > 0 then 'FAIL (บริษัทที่จ่ายครบหมดยังโผล่)'
           when n_rows = 3 and txt = expected then 'PASS'
           else 'FAIL (' || coalesce(replace(txt, tag_z || ' ', ''), 'ไม่มีแถว') || ')' end];

    select string_agg(right(b.company_name, 1), ',' order by b.seq) into txt
    from public.stats_company_balance b where b.company_name like tag_z || '%';
    res := res || array['19', 'ลำดับยอดค้าง: เรียงมาก → น้อย (d, e, a) — แอปแสดง 5 อันดับแรกจากลำดับนี้',
      case when txt = 'd,e,a' then 'PASS (d, e, a)' else format('FAIL (%s)', coalesce(txt, 'ไม่มีแถว')) end];

    select b.pct_of_outstanding into exp_pct from public.stats_company_balance b
     where b.company_name = tag_z || ' d';
    d_amt := trunc(7000.00 / (s1_ov ->> 'outstanding_total')::numeric * 100, 2);
    res := res || array['20', format('สัดส่วนของ d ต่อยอดค้างทั้งระบบ = trunc(7,000 / %s × 100, 2) = %s%%',
                                     s1_ov ->> 'outstanding_total', d_amt),
      case when exp_pct = d_amt then 'PASS (' || exp_pct || '%)'
           else format('FAIL (view ให้ %s%% แต่คำนวณได้ %s%%)', exp_pct, d_amt) end];

    select b.cum_pct into exp_pct from public.stats_company_balance b order by b.seq desc limit 1;
    select count(*) into n_bad from (
      select b.cum_pct - lag(b.cum_pct) over (order by b.seq) as diff
      from public.stats_company_balance b
    ) q where q.diff < 0;
    res := res || array['21', 'สัดส่วนสะสม (cum_pct): แถวสุดท้าย = 100.00% และเพิ่มขึ้นเสมอ (ใช้พูด "5 อันดับนี้รวมกัน X%")',
      case when exp_pct = 100.00 and n_bad = 0 then 'PASS'
           else format('FAIL (แถวสุดท้าย %s%% · มี %s แถวที่ลดลง)', exp_pct, n_bad) end];

    -- -----------------------------------------------------------------------
    -- เพิ่มข้อมูลของส่วน 1: เดือน MF และ MF1 (ไม่มีการ์ดจริงปน — ตรวจด้วย n_bad ข้อ 22)
    -- -----------------------------------------------------------------------
    insert into public.companies (name) values (tag_z || ' f') returning id into comp_f;
    insert into public.companies (name) values (tag_z || ' g') returning id into comp_g;

    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_f, (m0 - interval '1 month')::date, 10000, 30, mf, mf, mf + 10)
    returning id into card_x;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_x, 1234.56, 'transfer', today, '13:00');

    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_g, (m0 - interval '1 month')::date, 8000, 30, mf1, mf1, mf1 + 5)
    returning id into card_x;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_x, 8000, 'transfer', today, '14:00');
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_g, (m0 - interval '2 months')::date, 2000, 30, mf1, mf1, mf1 + 6);

    -- -----------------------------------------------------------------------
    -- 22: เก็บเงินของเดือน MF — 10,000 เก็บได้ 1,234.56 → 12.3456% ต้องได้ 12.34 (**ตัด ไม่ปัด**)
    -- -----------------------------------------------------------------------
    select count(*) into n_bad from public.stats_cards
     where due_month in (mf, mf1) and company_name not like tag_z || '%';
    select * into v from public.stats_collection_by_month where due_month = mf;
    res := res || array['22', 'เดือน MF: 1 ใบ · ต้องได้รับ 10,000.00 · เก็บได้ 1,234.56 · คงเหลือ 8,765.44 · เก็บได้ 12.34% (ตัดทศนิยม ไม่ปัดขึ้นเป็น 12.35)',
      case when n_bad > 0 then format('FAIL (มีการ์ดอื่นในเดือนทดสอบ %s ใบ — มีการ์ดจริงครบกำหนดอีก 13–14 เดือน?)', n_bad)
           when v.card_count = 1 and v.paid_card_count = 0 and v.due_total = 10000.00
            and v.collected_total = 1234.56 and v.balance_total = 8765.44
            and v.collected_pct = 12.34
           then 'PASS'
           else format('FAIL (%s ใบ / %s / %s / %s / %s%%)',
                       v.card_count, v.due_total, v.collected_total, v.balance_total, v.collected_pct) end];

    -- -----------------------------------------------------------------------
    -- 23: เดือน MF1 — การ์ดที่จ่ายครบแล้วยังถูกนับอยู่ในเดือนนั้น (ไม่หายไปจากตัวหาร)
    -- -----------------------------------------------------------------------
    select * into v from public.stats_collection_by_month where due_month = mf1;
    res := res || array['23', 'เดือน MF1: 2 ใบ (จ่ายครบ 1 ใบยังอยู่ในเดือนนั้น) · ต้องได้รับ 10,000.00 · เก็บได้ 8,000.00 · 80.00%',
      case when v.card_count = 2 and v.paid_card_count = 1 and v.due_total = 10000.00
            and v.collected_total = 8000.00 and v.balance_total = 2000.00
            and v.collected_pct = 80.00
           then 'PASS'
           else format('FAIL (%s ใบ / จ่ายครบ %s / %s / %s / %s%%)',
                       v.card_count, v.paid_card_count, v.due_total, v.collected_total, v.collected_pct) end];

    -- -----------------------------------------------------------------------
    -- 24: เดือนที่ไม่มีการ์ดเลย = **ไม่มีแถว** (แอปแสดงสถานะว่าง ไม่ใช่เขียนเลข 0 เอง)
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.stats_collection_by_month where due_month = mf2;
    res := res || array['24', 'เดือนที่ไม่มีการ์ดเลย: ไม่มีแถว (แอปต้องแสดงสถานะว่าง ไม่ใช่เขียนเลข 0 ขึ้นเอง)',
      case when n_rows = 0 then 'PASS' else format('FAIL (%s แถว)', n_rows) end];

    -- -----------------------------------------------------------------------
    -- 25: ตัวเลขของหน้าสถิติต้องตรงกับหน้าสรุปรายเดือนของเดือนเดียวกัน
    --     (monthly_report_total ของ 006 — ลูกค้าเอา 2 หน้ามาวางเทียบกันได้)
    -- -----------------------------------------------------------------------
    select s.due_total, s.balance_total, s.card_count, t.total_amount_sum, t.balance_sum, t.card_count as t_cnt
      into v
    from public.stats_collection_by_month s
    join public.monthly_report_total t on t.due_month = s.due_month
    where s.due_month = mf;
    -- monthly_report ไม่ได้กรองบริษัท [TEST] ออก (รายงานรายเดือนนับทุกบริษัท)
    -- ถ้ามีการ์ดอื่นในเดือนทดสอบ 2 ยอดจะต่างกันโดยไม่ใช่ความผิดของ view
    select count(*) into n_bad from public.monthly_report
     where due_month = mf and company_name not like tag_z || '%';
    res := res || array['25', 'เดือน MF: ยอดของ stats_collection_by_month = ยอดของ monthly_report_total (หน้าสถิติกับหน้ารายงานตรงกัน)',
      case when n_bad > 0 then format('FAIL (มีการ์ดอื่นในเดือนทดสอบ %s ใบ — รวมบริษัท [TEST] ที่รายงานรายเดือนนับด้วย)', n_bad)
           when v.due_total = v.total_amount_sum and v.balance_total = v.balance_sum
            and v.card_count = v.t_cnt
           then 'PASS'
           else format('FAIL (สถิติ %s / %s / %s ใบ · รายงาน %s / %s / %s ใบ)',
                       v.due_total, v.balance_total, v.card_count,
                       v.total_amount_sum, v.balance_sum, v.t_cnt) end];

    -- -----------------------------------------------------------------------
    -- S2 → เพิ่มบริษัท [TEST] → S3: ต้องไม่มีอะไรขยับแม้แต่สตางค์
    --   การ์ดของ [TEST] ตั้งใจวางในเดือน MF และมีทั้งยอดค้างและยอดที่จ่ายแล้ว
    --   ถ้าหลุดเข้ามาจะเห็นได้ทั้งในภาพรวม อายุหนี้ และ % ที่เก็บได้ของเดือน MF
    -- -----------------------------------------------------------------------
    select jsonb_object_agg(g.bucket, jsonb_build_array(g.balance_total, g.card_count))
      into s2_aging from public.stats_aging g;
    select to_jsonb(o) into s2_ov from public.stats_overview o;
    select to_jsonb(c) into s2_coll from public.stats_collection_by_month c where c.due_month = mf;
    select count(*) into n_cards0 from public.stats_cards;

    insert into public.companies (name) values (tag_t || ' x') returning id into comp_t;
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_t, (m0 - interval '1 month')::date, 50000, 30, mf, mf, mf + 12)
    returning id into card_x;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_x, 10000, 'transfer', today, '15:00');
    -- และอีก 1 ใบที่เลยกำหนดแล้ว (ถ้าหลุด จะเห็นในกลุ่มอายุหนี้ด้วย)
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_t, (m0 - interval '2 months')::date, 9000, 30, today - 100, today - 100, today - 70);

    select jsonb_object_agg(g.bucket, jsonb_build_array(g.balance_total, g.card_count))
      into s3_aging from public.stats_aging g;
    select to_jsonb(o) into s3_ov from public.stats_overview o;
    select to_jsonb(c) into s3_coll from public.stats_collection_by_month c where c.due_month = mf;
    select count(*) into n_cards1 from public.stats_cards;

    -- 26
    select count(*) into n_bad from public.stats_cards where company_name like '[TEST]%';
    res := res || array['26', 'บริษัท [TEST]: เพิ่มการ์ด 2 ใบ (59,000) แล้ว stats_cards ต้องไม่เปลี่ยนจำนวน และไม่มีชื่อ [TEST] เลย',
      case when n_cards1 = n_cards0 and n_bad = 0 then 'PASS'
           else format('FAIL (การ์ด %s → %s · ชื่อ [TEST] ใน stats_cards %s แถว)', n_cards0, n_cards1, n_bad) end];
    -- 27
    res := res || array['27', 'บริษัท [TEST]: stats_overview เท่าเดิมทุกช่อง (ยอดค้าง / เลยกำหนด / จำนวนบริษัท / data_since)',
      case when s3_ov = s2_ov then 'PASS'
           else format('FAIL (ก่อน %s · หลัง %s)', s2_ov, s3_ov) end];
    -- 28
    res := res || array['28', 'บริษัท [TEST]: stats_aging เท่าเดิมทั้ง 4 กลุ่ม (ใบที่เลยกำหนด 70 วันของ [TEST] ไม่หลุดเข้ามา)',
      case when s3_aging = s2_aging then 'PASS'
           else format('FAIL (ก่อน %s · หลัง %s)', s2_aging, s3_aging) end];
    -- 29
    res := res || array['29', 'บริษัท [TEST]: % ที่เก็บได้ของเดือน MF เท่าเดิม (การ์ด [TEST] อยู่ในเดือนนั้นแต่ไม่ถูกนับ)',
      case when s3_coll = s2_coll then 'PASS'
           else format('FAIL (ก่อน %s · หลัง %s)', s2_coll, s3_coll) end];
    -- 30
    select (select count(*) from public.stats_company_behavior where company_name like '[TEST]%')
         + (select count(*) from public.stats_company_balance  where company_name like '[TEST]%')
      into n_bad;
    res := res || array['30', 'บริษัท [TEST]: ไม่โผล่ใน stats_company_behavior และ stats_company_balance',
      case when n_bad = 0 then 'PASS' else format('FAIL (%s แถว)', n_bad) end];

    -- -----------------------------------------------------------------------
    -- 31: การ์ดที่ยกเลิกไม่ถูกนับ — เพิ่ม 3,000 แล้วยกเลิก ยอดต้องกลับเท่าเดิมเป๊ะ
    -- -----------------------------------------------------------------------
    insert into public.companies (name) values (tag_z || ' h') returning id into comp_h;
    insert into public.receivables
      (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_h, (m0 - interval '1 month')::date, 3000, 30, today - 40, today - 40, today - 10)
    returning id into card_h;
    select (o.outstanding_total) into d_amt from public.stats_overview o;
    update public.receivables set is_cancelled = true where id = card_h;
    select (o.outstanding_total) into d_amt2 from public.stats_overview o;
    res := res || array['31', 'การ์ดที่ยกเลิกไม่ถูกนับ: เพิ่ม 3,000.00 แล้วยกเลิก → ยอดค้างกลับเท่าเดิมเป๊ะ',
      case when d_amt = (s3_ov ->> 'outstanding_total')::numeric + 3000.00
            and d_amt2 = (s3_ov ->> 'outstanding_total')::numeric
           then 'PASS'
           else format('FAIL (ก่อน %s · เพิ่มแล้ว %s · ยกเลิกแล้ว %s)',
                       s3_ov ->> 'outstanding_total', d_amt, d_amt2) end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 32: owner อ่านได้ และได้ตัวเลขชุดเดียวกับ sales ทั้ง 6 view
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    select to_jsonb(o) into ow_ov from public.stats_overview o;
    select count(*) into n_rows from public.stats_company_behavior where company_name like tag_z || '%';
    select count(*) into n_bad  from public.stats_company_balance  where company_name like tag_z || '%';
    res := res || array['32', 'owner: อ่านทั้ง 6 view ได้ และได้ตัวเลขเดียวกับ sales (เจ้าของเปิดหน้าสถิติเองได้) · พฤติกรรม 7 บริษัท · ยอดค้าง 5 บริษัท (h ที่ยกเลิกการ์ดแล้วไม่โผล่ทั้ง 2 view)',
      case when ow_ov = s3_ov and n_rows = 7 and n_bad = 5 then 'PASS'
           else format('FAIL (ภาพรวมต่างกัน: %s · พฤติกรรม %s บริษัท · ยอดค้าง %s บริษัท)',
                       (ow_ov <> s3_ov), n_rows, n_bad) end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 33: anon (ไม่ล็อกอิน) อ่านทั้ง 6 view ไม่ได้
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    outcome := 'PASS (permission denied ทั้ง 6 view)';
    for v in select * from (values
        ('stats_cards'), ('stats_overview'), ('stats_collection_by_month'),
        ('stats_aging'), ('stats_company_behavior'), ('stats_company_balance')
      ) q(viewname)
    loop
      begin
        execute format('select count(*) from public.%I', v.viewname) into n_rows;
        outcome := format('FAIL (%s อ่านได้ %s แถว)', v.viewname, n_rows);
      exception when insufficient_privilege then null;
      end;
    end loop;
    reset role;
    res := res || array['33', 'anon: อ่านทั้ง 6 view ไม่ได้', outcome];

    -- -----------------------------------------------------------------------
    -- 34: บัญชีที่ถูกปิด (is_active = false → my_role() เป็น null) ได้ 0 แถวทั้ง 6 view
    --     รวม stats_overview และ stats_aging ที่แถวไม่ได้มาจากตาราง จึงต้องกรองด้วยเงื่อนไขของตัวเอง
    -- -----------------------------------------------------------------------
    update public.profiles set is_active = false where id = sales_id;
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    note := '';
    for v in select * from (values
        ('stats_cards'), ('stats_overview'), ('stats_collection_by_month'),
        ('stats_aging'), ('stats_company_behavior'), ('stats_company_balance')
      ) q(viewname)
    loop
      execute format('select count(*) from public.%I', v.viewname) into n_rows;
      if n_rows <> 0 then note := note || format(' [%s %s แถว]', v.viewname, n_rows); end if;
    end loop;
    reset role;
    res := res || array['34', 'บัญชีที่ is_active = false: อ่านได้ 0 แถวทั้ง 6 view (รวม stats_overview และ stats_aging)',
      case when note = '' then 'PASS (0 แถวทั้ง 6 view)' else 'FAIL' || note end];
    update public.profiles set is_active = true where id = sales_id;

    -- -----------------------------------------------------------------------
    -- 35–52: ไม่มีใครเขียนได้ — ทดลองทั้ง owner และ sales ต้องถูกปฏิเสธทั้งคู่
    --   6 view × insert / update / delete · view เหล่านี้ไม่มี grant เขียนให้ใคร (42501)
    --   และไม่ auto-updatable อยู่แล้ว (มี join / lateral / group by / window → 55000 / 0L000)
    --   insert เขียนเป็น "select * from ตัวมันเอง limit 1" เพื่อไม่ต้องไล่ชื่อคอลัมน์
    --   ทุกคำสั่งที่เผลอสำเร็จถูก rollback ทันทีด้วย raise 'stats_undo' ใน subtransaction
    -- -----------------------------------------------------------------------
    for w in
      select * from (values
        (35, 'insert stats_cards (ปั้นการ์ดเข้าสถิติ)',
             'insert into public.stats_cards select * from public.stats_cards limit 1'),
        (36, 'update stats_cards (แก้ยอดคงเหลือในสถิติ)',
             format('update public.stats_cards set balance = 0 where company_name like %L', tag_z || '%')),
        (37, 'delete stats_cards (เอาการ์ดออกจากสถิติ)',
             format('delete from public.stats_cards where company_name like %L', tag_z || '%')),
        (38, 'insert stats_overview (ปั้นภาพรวมเอง)',
             'insert into public.stats_overview select * from public.stats_overview limit 1'),
        (39, 'update stats_overview (แก้ยอดค้างรวม)',
             'update public.stats_overview set outstanding_total = 0 where card_count >= 0'),
        (40, 'delete stats_overview',
             'delete from public.stats_overview where card_count >= 0'),
        (41, 'insert stats_collection_by_month (ปั้นเดือนขึ้นมา)',
             'insert into public.stats_collection_by_month select * from public.stats_collection_by_month limit 1'),
        (42, 'update stats_collection_by_month (แก้ % ที่เก็บได้)',
             format('update public.stats_collection_by_month set collected_pct = 100 where due_month = %L', mf)),
        (43, 'delete stats_collection_by_month (ลบเดือนออกจากสถิติ)',
             format('delete from public.stats_collection_by_month where due_month = %L', mf)),
        (44, 'insert stats_aging (เพิ่มกลุ่มอายุหนี้)',
             'insert into public.stats_aging select * from public.stats_aging limit 1'),
        (45, 'update stats_aging (แก้ยอดของกลุ่ม)',
             'update public.stats_aging set balance_total = 0 where bucket = ''d60_plus'''),
        (46, 'delete stats_aging (ลบกลุ่มเกิน 60 วันให้หายไป)',
             'delete from public.stats_aging where bucket = ''d60_plus'''),
        (47, 'insert stats_company_behavior (ปั้นบริษัทขึ้นมา)',
             'insert into public.stats_company_behavior select * from public.stats_company_behavior limit 1'),
        (48, 'update stats_company_behavior (แก้วันช้าเฉลี่ยให้ดูดีขึ้น)',
             format('update public.stats_company_behavior set avg_late_days = 0 where company_name like %L', tag_z || '%')),
        (49, 'delete stats_company_behavior (ซ่อนบริษัทที่จ่ายช้า)',
             format('delete from public.stats_company_behavior where company_name like %L', tag_z || '%')),
        (50, 'insert stats_company_balance',
             'insert into public.stats_company_balance select * from public.stats_company_balance limit 1'),
        (51, 'update stats_company_balance (แก้ยอดค้างของบริษัท)',
             format('update public.stats_company_balance set balance_total = 0 where company_name like %L', tag_z || '%')),
        (52, 'delete stats_company_balance',
             format('delete from public.stats_company_balance where company_name like %L', tag_z || '%'))
      ) t(n, label, stmt)
    loop
      all_denied := true;
      note := '';
      for r2 in select * from (values ('sales', sales_claims), ('owner', owner_claims)) q(who, claims)
      loop
        perform set_config('request.jwt.claims', r2.claims, true);
        set local role authenticated;
        begin
          execute w.stmt;
          get diagnostics n_rows = row_count;
          all_denied := false;
          note := note || format(' [%s เขียนได้ %s แถว]', r2.who, n_rows);
          raise exception 'stats_undo';
        exception
          when raise_exception then
            if sqlerrm <> 'stats_undo' then
              all_denied := false;
              note := note || format(' [%s %s]', r2.who, sqlerrm);
            end if;
          when others then
            -- 42501 = ไม่มีสิทธิ์ (ที่ควรเกิด) · 55000 / 0L000 = view แก้ไขไม่ได้ ก็เขียนไม่ได้เหมือนกัน
            if sqlstate not in ('42501', '55000', '0L000') then
              all_denied := false;
              note := note || format(' [%s %s %s]', r2.who, sqlstate, sqlerrm);
            end if;
        end;
        reset role;
      end loop;
      res := res || array[w.n::text, w.label || ' → ต้องถูกปฏิเสธทั้ง owner และ sales',
        case when all_denied then 'PASS (เขียนไม่ได้ทั้ง 2 role)' else 'FAIL' || note end];
    end loop;

    raise exception 'stats_undo';
  exception when raise_exception then
    if sqlerrm <> 'stats_undo' then raise; end if;
  end;
  reset role;

  insert into stats_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

-- ---------------------------------------------------------------------------
-- 53–55: ตรวจโครงสร้าง (ไม่ต้องเขียนข้อมูล) — **เก็บลง stats_results เหมือนข้อ 1–52**
--   เพราะ Supabase SQL Editor แสดงเฉพาะ result set สุดท้ายของไฟล์
--   53 เป็น view จริงและตั้ง security_invoker = true (ใช้ RLS ของคนที่อ่าน)
--   54 สิทธิ์ระดับตาราง: authenticated ได้แค่ SELECT · anon ไม่ได้อะไรเลย
--   55 คอลัมน์ตรงกับ schema.md ข้อ 4.5 (ชื่อ ชนิด ลำดับ — แอปอ่านตามนี้)
-- ---------------------------------------------------------------------------
insert into stats_results (n, test, result)
select
  53                                                                   as n,
  'view + security_invoker: ' || x.viewname                            as test,
  case
    when c.relkind <> 'v' then 'FAIL (ไม่ใช่ view)'
    when c.reloptions::text like '%security_invoker=true%' then 'PASS'
    else 'FAIL (ไม่ได้ตั้ง security_invoker → ใช้สิทธิ์ของเจ้าของ view)'
  end                                                                  as result
from (values
  ('stats_cards'), ('stats_overview'), ('stats_collection_by_month'),
  ('stats_aging'), ('stats_company_behavior'), ('stats_company_balance')
) as x(viewname)
join pg_class c on c.oid = ('public.' || x.viewname)::regclass
union all
select
  54,
  'สิทธิ์ระดับตาราง (authenticated / anon): ' || x.viewname,
  case
    when exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.viewname and g.grantee = 'anon'
    ) then 'FAIL (anon มีสิทธิ์)'
    when (
      select coalesce(string_agg(distinct g.privilege_type, ',' order by g.privilege_type), '')
      from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.viewname and g.grantee = 'authenticated'
    ) = 'SELECT' then 'PASS (select เท่านั้น)'
    else 'FAIL (' || (
      select coalesce(string_agg(distinct g.privilege_type, ',' order by g.privilege_type), 'ไม่มีสิทธิ์')
      from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.viewname and g.grantee = 'authenticated'
    ) || ')'
  end
from (values
  ('stats_cards'), ('stats_overview'), ('stats_collection_by_month'),
  ('stats_aging'), ('stats_company_behavior'), ('stats_company_balance')
) as x(viewname)
union all
select
  55,
  'คอลัมน์ตาม schema.md 4.5: ' || x.viewname,
  case when got.cols = x.want then 'PASS' else 'FAIL (ได้ ' || got.cols || ')' end
from (values
  ('stats_cards',
   'id,company_id,company_name,due_month,account_month,total_amount,paid_amount,balance,is_paid,actual_due_date,days_to_actual_due,paid_late_actual_days,created_at'),
  ('stats_overview',
   'today,data_since,company_count,card_count,outstanding_total,outstanding_card_count,overdue_total,overdue_card_count'),
  ('stats_collection_by_month',
   'due_month,card_count,paid_card_count,due_total,collected_total,balance_total,collected_pct'),
  ('stats_aging',
   'bucket,bucket_order,balance_total,card_count,pct_of_outstanding'),
  ('stats_company_behavior',
   'seq,company_id,company_name,card_count,paid_card_count,on_time_count,late_card_count,on_time_pct,avg_late_days,max_late_days,overdue_now_count,overdue_now_total,open_card_count,open_total,is_thin'),
  ('stats_company_balance',
   'seq,company_id,company_name,balance_total,open_card_count,overdue_card_count,pct_of_outstanding,cum_pct')
) as x(viewname, want)
cross join lateral (
  select coalesce(string_agg(col.column_name, ',' order by col.ordinal_position), '(ไม่พบ view)') as cols
  from information_schema.columns col
  where col.table_schema = 'public' and col.table_name = x.viewname
) got;

-- ---------------------------------------------------------------------------
-- 56: **ยามเฝ้า rollback** — ข้อมูลทดสอบทั้ง 2 ชุดต้องไม่เหลืออยู่ในฐานข้อมูลจริง
--   ข้อนี้ตรวจ *หลัง* block ข้างบนจบแล้ว (ทุกอย่างถูก rollback ไปแล้ว)
--   ZZ-STATS-CHECK ไม่มี prefix [TEST] จึงถูกนับในสถิติและในรายงานความสำเร็จ
--   ถ้าข้อนี้ FAIL ต้องเก็บกวาดทันที (วิธีอยู่ในหัวไฟล์) ไม่งั้นตัวเลขของลูกค้าจะเพี้ยน
-- ---------------------------------------------------------------------------
insert into stats_results (n, test, result)
select
  56,
  'หลัง rollback: ไม่มีบริษัท ZZ-STATS-CHECK / [TEST] stats ค้างในฐานข้อมูล',
  case when z.n = 0 and t.n = 0 then 'PASS (ข้อมูลทดสอบไม่เหลือ)'
       else format('FAIL (ZZ-STATS-CHECK %s บริษัท · [TEST] stats %s บริษัท — ดูวิธีเก็บกวาดที่หัวไฟล์)', z.n, t.n) end
from (select count(*) as n from public.companies where name like 'ZZ-STATS-CHECK%') z
cross join (select count(*) as n from public.companies where name like '[TEST] stats%') t;

-- ---------------------------------------------------------------------------
-- ผลทั้งหมดใน result set เดียว: แถวสรุป (ข้อ 0) บนสุด แล้วข้อ 1–56 เรียงตามหมายเลข
-- ทุกผลที่ผ่านขึ้นต้นด้วย "PASS" จึงนับด้วย like 'PASS%' ได้ตรง ๆ
-- ---------------------------------------------------------------------------
with summary as (
  select count(*) filter (where result like 'PASS%') as passed, count(*) as total
  from stats_results
)
select 0                                                                  as n,
       format('สรุป: PASS %s / %s ข้อ', s.passed, s.total)                as test,
       case when s.passed = s.total then 'ALL PASS' else 'HAS FAIL' end   as result
from summary s
union all
select n, test, result from stats_results
order by n;
