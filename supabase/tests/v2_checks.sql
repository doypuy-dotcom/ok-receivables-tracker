-- v2_checks.sql — ตรวจ 3 view ของหน้าสรุปรายเดือน (V2) แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 006_monthly_report.sql)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบ (บริษัท "[TEST] v2 …") และทุกการเขียนที่ทดลองถูก rollback เสมอ
-- **ผลทุกข้อออกมาใน result set เดียวที่ท้ายไฟล์** (SQL Editor แสดงเฉพาะชุดสุดท้าย):
--   ข้อ 0 = แถวสรุป "PASS x / y ข้อ" + ALL PASS หรือ HAS FAIL · ข้อ 1–28 = ผลแต่ละข้อ
--   ทุกข้อเก็บลง temp table v2_results ก่อน แล้วค่อย select ครั้งเดียว
-- [สั่ง N] = ข้อที่สั่งให้ตรวจใน V2, [+] = ข้อตรวจเพิ่ม
--   สั่ง 1 = owner และ sales อ่านได้ทั้งคู่            → ข้อ 1, 2, 14
--   สั่ง 2 = ไม่มีใครเขียนได้                         → ข้อ 16–24, 27
--   สั่ง 3 = เงินทุกตัวรวมยอดรวมมาจาก database        → ข้อ 4, 5
--   สั่ง 4 = บล็อกค้างข้ามเดือนใช้ due_month < เดือนที่เลือก and not is_paid
--            **ไม่ใช่ is_carried_over**               → ข้อ 10, 11, 12, 13, 28
--
-- ข้อมูลทดสอบ 6 บริษัท (ชื่อ "<tag> a" … "<tag> f") — ตั้งใจวางไว้ 2 ที่:
--   เดือน MF = อีก 13 เดือน  → **ไม่มีการ์ดจริงปน** จึงตรวจยอดรวมเป็นตัวเลขเป๊ะได้
--     a  10,000 จ่าย 2,500  ครบกำหนด MF+20  → คงเหลือ 7,500
--     b   8,000 จ่าย 8,000  ครบกำหนด MF+5   → คงเหลือ 0.00 (จ่ายครบ ต้องยังอยู่ในตาราง)
--     c   1,234.56 ไม่จ่าย  ครบกำหนด MF+5   → ทดสอบการตัดลำดับด้วยชื่อบริษัทเมื่อวันครบกำหนดเท่ากัน
--     d   5,000 การ์ดถูกยกเลิก               → ต้องไม่โผล่ที่ไหนเลย
--   เดือน MF+1 → e 3,000 ไม่จ่าย (ให้เดือนนั้นมีแถวในตาราง)
--   เดือนก่อน   → f 4,200 ไม่จ่าย = การ์ดที่ is_carried_over = true ของจริง (ใช้ในข้อ 12)

create temp table if not exists v2_results (n int, test text, result text);
truncate v2_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today   constant date := (now() at time zone 'Asia/Bangkok')::date;
  lm      constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) - interval '1 month')::date;
  mf      constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '13 months')::date;
  mf1     constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '14 months')::date;
  mf_prev constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) + interval '12 months')::date;
  tag     constant text := '[TEST] v2 ' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  owner_claims text;
  sales_claims text;
  comp_a uuid; comp_b uuid; comp_c uuid; comp_d uuid; comp_e uuid; comp_f uuid;
  card_a uuid; card_b uuid; card_c uuid; card_d uuid; card_e uuid; card_f uuid;
  res text[] := '{}';
  v record;
  w record;
  r2 record;
  outcome text;
  txt text;
  expected text;
  n_rows int;
  n_bad int;
  n_asof int;
  b_carry boolean;
  all_denied boolean;
  note text;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;
  owner_claims := json_build_object('sub', owner_id, 'role', 'authenticated')::text;
  sales_claims := json_build_object('sub', sales_id, 'role', 'authenticated')::text;

  begin  -- ทุกอย่างใน block นี้ถูก rollback ตอนจบ (raise 'v2_undo')

    -- -----------------------------------------------------------------------
    -- เตรียมข้อมูล (เขียนในนามบัญชี sales ผ่าน RLS + trigger จริง)
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;

    insert into public.companies (name) values (tag || ' a') returning id into comp_a;
    insert into public.companies (name) values (tag || ' b') returning id into comp_b;
    insert into public.companies (name) values (tag || ' c') returning id into comp_c;
    insert into public.companies (name) values (tag || ' d') returning id into comp_d;
    insert into public.companies (name) values (tag || ' e') returning id into comp_e;
    insert into public.companies (name) values (tag || ' f') returning id into comp_f;

    -- เดือน MF (อีก 13 เดือน) — b และ c ครบกำหนดวันเดียวกัน เพื่อทดสอบการตัดลำดับด้วยชื่อบริษัท
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, mf_prev, 10000, 60, mf_prev, mf_prev, mf + 20) returning id into card_a;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_b, mf_prev, 8000, 30, mf_prev, mf_prev, mf + 5) returning id into card_b;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_c, mf_prev, 1234.56, 30, mf_prev, mf_prev, mf + 5) returning id into card_c;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_d, mf_prev, 5000, 30, mf_prev, mf_prev, mf + 20) returning id into card_d;
    update public.receivables set is_cancelled = true where id = card_d;

    -- เดือน MF+1 และ "เดือนก่อน" (ของจริง → is_carried_over = true)
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_e, mf, 3000, 30, mf, mf, mf1 + 10) returning id into card_e;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_f, (lm - interval '1 month')::date, 4200, 30, lm, lm, lm + 2) returning id into card_f;

    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_a, 2500, 'transfer', today, '10:00');
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_b, 8000, 'cheque', today, '11:00');

    -- -----------------------------------------------------------------------
    -- 1–2: [สั่ง 1] อ่านได้ทั้ง 2 role และการ์ดที่ยกเลิกไม่โผล่
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.monthly_report where company_name like tag || '%';
    select count(*) into n_bad  from public.monthly_report where receivable_id = card_d;
    res := res || array['1', '[สั่ง 1] sales: อ่าน monthly_report ได้ เห็นการ์ดทดสอบ 5 ใบ (การ์ดที่ยกเลิกไม่โผล่)',
      case when n_rows = 5 and n_bad = 0 then 'PASS'
           else format('FAIL (เห็น %s ใบ, การ์ดที่ยกเลิก %s แถว)', n_rows, n_bad) end];
    reset role;

    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.monthly_report where company_name like tag || '%';
    select count(*) into n_bad  from public.monthly_report where receivable_id = card_d;
    res := res || array['2', '[สั่ง 1] owner: อ่าน monthly_report ได้เหมือน sales (เจ้าของเปิดรายงานเองได้)',
      case when n_rows = 5 and n_bad = 0 then 'PASS'
           else format('FAIL (เห็น %s ใบ, การ์ดที่ยกเลิก %s แถว)', n_rows, n_bad) end];

    -- -----------------------------------------------------------------------
    -- 3: ลำดับในเดือน = row_number() ของ database เรียงตามวันครบกำหนดจริง
    --    วันครบกำหนดเท่ากัน (b และ c) → ตัดด้วยชื่อบริษัท → b, c, a
    -- -----------------------------------------------------------------------
    select count(*) into n_bad from public.monthly_report
    where due_month = mf and company_name not like tag || '%';
    select string_agg(company_name || '#' || seq, ' | ' order by seq) into txt
    from public.monthly_report where due_month = mf;
    expected := format('%s b#1 | %s c#2 | %s a#3', tag, tag, tag);
    res := res || array['3', '[+] ลำดับในเดือน: เรียงตาม actual_due_date และตัดด้วยชื่อบริษัทเมื่อวันเท่ากัน (b, c, a) เริ่มที่ 1',
      case when n_bad > 0 then format('FAIL (มีการ์ดอื่นในเดือนทดสอบ %s แถว — มีการ์ดจริงครบกำหนดอีก 13 เดือน?)', n_bad)
           when txt = expected then 'PASS (b#1 | c#2 | a#3)'
           else 'FAIL (' || coalesce(replace(txt, tag, '…'), 'ไม่มีแถว') || ')' end];

    -- -----------------------------------------------------------------------
    -- 4: [สั่ง 3] แถว "ยอดรวม" มาจาก database และตรงเป๊ะถึงสตางค์
    --    10,000 + 8,000 + 1,234.56 = 19,234.56 · คงเหลือ 7,500 + 0 + 1,234.56 = 8,734.56
    -- -----------------------------------------------------------------------
    select card_count, total_amount_sum, balance_sum into v
    from public.monthly_report_total where due_month = mf;
    res := res || array['4', '[สั่ง 3] ยอดรวมของเดือน (monthly_report_total) = 3 ใบ / 19,234.56 / 8,734.56',
      case when v.card_count = 3 and v.total_amount_sum = 19234.56 and v.balance_sum = 8734.56 then 'PASS'
           else format('FAIL (%s ใบ / %s / %s)', v.card_count, v.total_amount_sum, v.balance_sum) end];

    -- -----------------------------------------------------------------------
    -- 5: [สั่ง 3] ยอดรวมของ **ทุกเดือนที่มองเห็น** ตรงกับผลรวมที่คำนวณอีกทางหนึ่ง
    --    จาก receivables + payments ตรง ๆ (ไม่ผ่าน receivable_summary)
    --    0 = ไม่มีเดือนไหนเพี้ยน และไม่มีเดือนไหนขาดหรือเกิน
    -- -----------------------------------------------------------------------
    with calc as (
      select date_trunc('month', r.actual_due_date::timestamp)::date as m,
             count(*)                                   as c,
             sum(r.total_amount)                        as ta,
             sum(r.total_amount - coalesce(p.paid, 0))  as bal
      from public.receivables r
      left join (
        select receivable_id, sum(amount) as paid
        from public.payments where not is_cancelled group by receivable_id
      ) p on p.receivable_id = r.id
      where not r.is_cancelled
      group by 1
    )
    select count(*) into n_bad
    from calc c
    full join public.monthly_report_total t on t.due_month = c.m
    where c.m is null or t.due_month is null
       or t.card_count <> c.c or t.total_amount_sum <> c.ta or t.balance_sum <> c.bal;
    res := res || array['5', '[สั่ง 3] ยอดรวมทุกเดือนตรงกับผลรวมที่คำนวณจาก receivables + payments อีกทางหนึ่ง',
      case when n_bad = 0 then 'PASS (ตรงทุกเดือน)' else 'FAIL (' || n_bad || ' เดือนไม่ตรง)' end];

    -- -----------------------------------------------------------------------
    -- 6–7: ลำดับใช้ได้จริงทุกเดือน (ไม่ใช่แค่เดือนทดสอบ)
    -- -----------------------------------------------------------------------
    select count(*) into n_bad from (
      select due_month, count(*) as c, min(seq) as mn, max(seq) as mx, count(distinct seq) as d
      from public.monthly_report group by due_month
    ) x where x.mn <> 1 or x.mx <> x.c or x.d <> x.c;
    res := res || array['6', '[+] ทุกเดือน: ลำดับเริ่มที่ 1 ไม่ซ้ำ และต่อเนื่องถึงจำนวนการ์ดในเดือนนั้น',
      case when n_bad = 0 then 'PASS' else 'FAIL (' || n_bad || ' เดือนลำดับไม่ต่อเนื่อง)' end];

    select count(*) into n_bad from (
      select actual_due_date,
             lag(actual_due_date) over (partition by due_month order by seq) as prev
      from public.monthly_report
    ) x where x.prev is not null and x.actual_due_date < x.prev;
    res := res || array['7', '[+] ทุกเดือน: เรียงตามลำดับแล้ววันครบกำหนดจริงไม่ย้อนหลัง (เร็ว → ช้า)',
      case when n_bad = 0 then 'PASS' else 'FAIL (' || n_bad || ' จุดเรียงผิด)' end];

    -- -----------------------------------------------------------------------
    -- 8: การ์ดที่จ่ายครบยังอยู่ในตาราง ยอดคงเหลือ 0.00 (ไม่มีคำว่า "จ่ายแล้ว" ไม่มีคอลัมน์สถานะ)
    -- -----------------------------------------------------------------------
    select balance::text as bal, is_paid as paid into v
    from public.monthly_report where receivable_id = card_b;
    res := res || array['8', '[+] การ์ดที่จ่ายครบยังอยู่ในตาราง และยอดคงเหลือเป็น 0.00',
      case when v.bal = '0.00' and v.paid then 'PASS (0.00)'
           else format('FAIL (balance=%s is_paid=%s)', v.bal, v.paid) end];

    -- -----------------------------------------------------------------------
    -- 9: การ์ดที่ยกเลิกไม่ถูกนับในยอดรวมด้วย (ไม่ใช่แค่ไม่โผล่ในตาราง)
    -- -----------------------------------------------------------------------
    select count(*) into n_bad from public.monthly_report where receivable_id = card_d;
    select card_count into n_rows from public.monthly_report_total where due_month = mf;
    res := res || array['9', '[+] การ์ดที่ยกเลิกไม่โผล่ในตารางและไม่ถูกนับในยอดรวม (5,000 ไม่เข้ายอด)',
      case when n_bad = 0 and n_rows = 3 then 'PASS'
           else format('FAIL (แถว %s, นับในยอดรวม %s ใบ)', n_bad, n_rows) end];

    -- -----------------------------------------------------------------------
    -- 10: [สั่ง 4] บล็อก "ยอดค้างข้ามเดือน" = due_month < เดือนที่เลือก  and  not is_paid
    --     เลือกเดือน MF+1 → ต้องได้ a (ค้าง), c (ค้าง), f (ค้างจากเดือนก่อนของจริง)
    --     ไม่ได้ b (จ่ายครบ), d (ยกเลิก), e (ครบกำหนดในเดือนที่เลือกเอง)
    -- -----------------------------------------------------------------------
    select coalesce(string_agg(company_name, ', ' order by company_name), '(ไม่มี)') into txt
    from public.monthly_report
    where due_month < mf1 and not is_paid and company_name like tag || '%';
    expected := format('%s a, %s c, %s f', tag, tag, tag);
    res := res || array['10', '[สั่ง 4] เลือกเดือน MF+1: บล็อกค้างข้ามเดือนได้ a, c, f (ไม่มี b ที่จ่ายครบ / d ที่ยกเลิก / e ของเดือนที่เลือก)',
      case when txt = expected then 'PASS (a, c, f)'
           else 'FAIL (' || replace(txt, tag, '…') || ')' end];

    -- -----------------------------------------------------------------------
    -- 11: เลือกเดือน MF → การ์ดของเดือนนั้นอยู่ในตาราง และบล็อกไม่มีการ์ดเหล่านั้นเลย
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.monthly_report
    where due_month = mf and receivable_id in (card_a, card_b, card_c);
    select count(*) into n_bad from public.monthly_report
    where due_month < mf and not is_paid and receivable_id in (card_a, card_b, card_c);
    res := res || array['11', '[สั่ง 4] เลือกเดือน MF: a, b, c อยู่ในตาราง 3 แถว และไม่โผล่ซ้ำในบล็อกค้างข้ามเดือน',
      case when n_rows = 3 and n_bad = 0 then 'PASS'
           else format('FAIL (ในตาราง %s แถว, ซ้ำในบล็อก %s แถว)', n_rows, n_bad) end];

    -- -----------------------------------------------------------------------
    -- 12: [สั่ง 4] **เหตุผลที่ห้ามใช้ is_carried_over ตรง ๆ**
    --     f ครบกำหนดเดือนก่อนและยังค้าง → receivable_summary.is_carried_over = true
    --     ถ้าเอา is_carried_over มาทำบล็อก แล้วผู้ใช้เลือก "เดือนก่อน"
    --     f จะโผล่ทั้งในตารางและในบล็อก (ซ้ำ) · เงื่อนไขที่ตกลงกันต้องไม่ซ้ำ
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.monthly_report
    where due_month = lm and receivable_id = card_f;
    select count(*) into n_bad from public.monthly_report
    where due_month < lm and not is_paid and receivable_id = card_f;
    select is_carried_over into b_carry from public.receivable_summary where id = card_f;
    res := res || array['12', '[สั่ง 4] เลือก "เดือนก่อน": f อยู่ในตาราง ไม่อยู่ในบล็อก ทั้งที่ is_carried_over = true (จึงห้ามใช้ is_carried_over)',
      case when n_rows = 1 and n_bad = 0 and b_carry then 'PASS'
           else format('FAIL (ในตาราง %s, ในบล็อก %s, is_carried_over=%s)', n_rows, n_bad, b_carry) end];

    -- -----------------------------------------------------------------------
    -- 13: 1 การ์ด = 1 แถวใน monthly_report → ตารางกับบล็อกไม่ซ้ำกันไม่ว่าเลือกเดือนไหน
    --     (due_month ของแถวมีค่าเดียว จะเป็นทั้ง "= เดือนที่เลือก" และ "< เดือนที่เลือก" ไม่ได้)
    -- -----------------------------------------------------------------------
    select count(*) into n_bad from (
      select receivable_id from public.monthly_report group by receivable_id having count(*) > 1
    ) z;
    res := res || array['13', '[สั่ง 4] 1 การ์ด = 1 แถวใน monthly_report (รากของการไม่ซ้ำระหว่างตารางกับบล็อก)',
      case when n_bad = 0 then 'PASS' else 'FAIL (' || n_bad || ' การ์ดมีหลายแถว)' end];

    -- -----------------------------------------------------------------------
    -- 14: [สั่ง 1] report_asof — "วันนี้" และเวลาที่ดู มาจาก database ตามเวลาไทย
    -- -----------------------------------------------------------------------
    select count(*) into n_rows from public.report_asof;
    -- ต้องเขียน a.today (ไม่ใช่ today เฉย ๆ): ชื่อคอลัมน์ชนกับตัวแปร today ของ block นี้
    select a.today as d, a.viewed_at as ts into v from public.report_asof a;
    res := res || array['14', '[สั่ง 1] owner: report_asof คืน 1 แถว · today = วันที่ตามเวลาไทย · viewed_at = now()',
      case when n_rows = 1 and v.d = today and v.ts = now() then 'PASS (' || v.d || ')'
           else format('FAIL (%s แถว, today=%s, viewed_at=%s)', n_rows, v.d, v.ts) end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 15: anon (ไม่ล็อกอิน) อ่านทั้ง 3 view ไม่ได้
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    begin
      select count(*) into n_rows from public.monthly_report;
      select count(*) into n_bad  from public.monthly_report_total;
      select count(*) into n_asof from public.report_asof;
      outcome := format('FAIL (อ่านได้: report %s, total %s, asof %s)', n_rows, n_bad, n_asof);
    exception when insufficient_privilege then outcome := 'PASS (permission denied)';
    end;
    reset role;
    res := res || array['15', '[+] anon: อ่าน monthly_report / monthly_report_total / report_asof', outcome];

    -- -----------------------------------------------------------------------
    -- 16–24: [สั่ง 2] ไม่มีใครเขียนได้ — ทดลองทั้ง owner และ sales ต้องถูกปฏิเสธทั้งคู่
    --     view เหล่านี้ไม่มี grant insert / update / delete ให้ใคร (→ 42501)
    --     และไม่ auto-updatable อยู่แล้ว (สร้างบน receivable_summary ที่มี join / lateral / group by)
    --     ทุกคำสั่งที่เผลอสำเร็จถูก rollback ทันทีด้วย raise 'v2_undo' ใน subtransaction
    -- -----------------------------------------------------------------------
    for w in
      select * from (values
        (16, 'insert monthly_report (ปั้นแถวในรายงาน)',
             format('insert into public.monthly_report (due_month, seq, receivable_id, company_name, credit_days, account_month, total_amount, balance, is_paid, actual_due_date) values (%L, 1, %L, %L, 30, %L, 1, 1, false, %L)',
                    mf, card_a, tag || ' x', mf_prev, mf)),
        (17, 'update monthly_report (แก้ชื่อบริษัทในรายงาน)',
             format('update public.monthly_report set company_name = %L where receivable_id = %L', 'แก้ชื่อ', card_a)),
        (18, 'delete monthly_report (ลบแถวในรายงาน)',
             format('delete from public.monthly_report where receivable_id = %L', card_a)),
        (19, 'insert monthly_report_total (ปั้นแถวยอดรวมเอง)',
             format('insert into public.monthly_report_total (due_month, card_count, total_amount_sum, balance_sum) values (%L, 1, 1, 1)', mf)),
        (20, 'update monthly_report_total (แก้ยอดรวม)',
             format('update public.monthly_report_total set balance_sum = 0 where due_month = %L', mf)),
        (21, 'delete monthly_report_total (ลบยอดรวม)',
             format('delete from public.monthly_report_total where due_month = %L', mf)),
        (22, 'insert report_asof (ปั้นวันที่/เวลาที่ดูเอง)',
             format('insert into public.report_asof (today, viewed_at) values (%L, now())', today)),
        (23, 'update report_asof (แก้วันที่ให้เพี้ยน)',
             format('update public.report_asof set today = %L where today is not null', today - 7)),
        (24, 'delete report_asof',
             'delete from public.report_asof where today is not null')
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
          raise exception 'v2_undo';
        exception
          when raise_exception then
            if sqlerrm <> 'v2_undo' then
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
      res := res || array[w.n::text, '[สั่ง 2] ' || w.label || ' → ต้องถูกปฏิเสธทั้ง owner และ sales',
        case when all_denied then 'PASS (เขียนไม่ได้ทั้ง 2 role)' else 'FAIL' || note end];
    end loop;

    -- -----------------------------------------------------------------------
    -- 25: บัญชีที่ถูกปิด (is_active = false → my_role() เป็น null) ไม่เห็นอะไรเลย
    --     รวม report_asof ที่ไม่ได้อ่านตารางไหน จึงต้องกรองด้วยเงื่อนไขของตัวเอง
    --     (การแก้ profiles ตรงนี้ถูก rollback ตอนจบ block เหมือนทุกอย่างในไฟล์นี้)
    -- -----------------------------------------------------------------------
    update public.profiles set is_active = false where id = sales_id;
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.monthly_report;
    select count(*) into n_bad  from public.monthly_report_total;
    select count(*) into n_asof from public.report_asof;
    reset role;
    res := res || array['25', '[+] บัญชีที่ is_active = false: อ่านทั้ง 3 view ได้ 0 แถว (รวม report_asof)',
      case when n_rows = 0 and n_bad = 0 and n_asof = 0 then 'PASS (0 แถวทั้ง 3 view)'
           else format('FAIL (report %s, total %s, asof %s)', n_rows, n_bad, n_asof) end];

    raise exception 'v2_undo';
  exception when raise_exception then
    if sqlerrm <> 'v2_undo' then raise; end if;
  end;
  reset role;

  insert into v2_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

-- ---------------------------------------------------------------------------
-- 26–28: ตรวจโครงสร้าง (ไม่ต้องเขียนข้อมูล) — **เก็บลง v2_results เหมือนข้อ 1–25**
--   เพราะ Supabase SQL Editor แสดงเฉพาะ result set สุดท้ายของไฟล์
--   ถ้าแยกเป็น select ของตัวเองจะเห็นแค่ข้อ 26–28 ผลข้อ 1–25 หายไป
--   26 เป็น view จริงและตั้ง security_invoker = true (ใช้ RLS ของคนที่อ่าน)
--   27 [สั่ง 2] สิทธิ์ระดับตาราง: authenticated ได้แค่ SELECT · anon ไม่ได้อะไรเลย
--   28 [สั่ง 4] คอลัมน์ตรงกับ schema.md ข้อ 4.3 — monthly_report ต้องมี is_paid
--      และ **ต้องไม่มี is_carried_over** (กันหยิบไปทำบล็อกค้างข้ามเดือนผิด)
-- ---------------------------------------------------------------------------
insert into v2_results (n, test, result)
select
  26                                                                   as n,
  'view + security_invoker: ' || x.viewname                            as test,
  case
    when c.relkind <> 'v' then 'FAIL (ไม่ใช่ view)'
    when c.reloptions::text like '%security_invoker=true%' then 'PASS'
    else 'FAIL (ไม่ได้ตั้ง security_invoker → ใช้สิทธิ์ของเจ้าของ view)'
  end                                                                  as result
from (values ('monthly_report'), ('monthly_report_total'), ('report_asof')) as x(viewname)
join pg_class c on c.oid = ('public.' || x.viewname)::regclass
union all
select
  27,
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
from (values ('monthly_report'), ('monthly_report_total'), ('report_asof')) as x(viewname)
union all
select
  28,
  'คอลัมน์ตาม schema.md 4.3: ' || x.viewname,
  case when got.cols = x.want then 'PASS' else 'FAIL (ได้ ' || got.cols || ')' end
from (values
  ('monthly_report',
   'due_month,seq,receivable_id,company_name,credit_days,account_month,total_amount,balance,is_paid,actual_due_date'),
  ('monthly_report_total', 'due_month,card_count,total_amount_sum,balance_sum'),
  ('report_asof', 'today,viewed_at')
) as x(viewname, want)
cross join lateral (
  select coalesce(string_agg(col.column_name, ',' order by col.ordinal_position), '(ไม่พบ view)') as cols
  from information_schema.columns col
  where col.table_schema = 'public' and col.table_name = x.viewname
) got;

-- ---------------------------------------------------------------------------
-- ผลทั้งหมดใน result set เดียว: แถวสรุป (ข้อ 0) บนสุด แล้วข้อ 1–28 เรียงตามหมายเลข
-- ทุกผลที่ผ่านขึ้นต้นด้วย "PASS" จึงนับด้วย like 'PASS%' ได้ตรง ๆ
-- ---------------------------------------------------------------------------
with summary as (
  select count(*) filter (where result like 'PASS%') as passed, count(*) as total
  from v2_results
)
select 0                                                                  as n,
       format('สรุป: PASS %s / %s ข้อ', s.passed, s.total)                as test,
       case when s.passed = s.total then 'ALL PASS' else 'HAS FAIL' end   as result
from summary s
union all
select n, test, result from v2_results
order by n;
