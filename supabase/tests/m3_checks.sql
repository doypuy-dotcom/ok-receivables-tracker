-- m3_checks.sql — ตรวจคอลัมน์ใหม่ของ receivable_summary (003_summary_paid_late.sql) แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 003)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบ (บริษัท "[TEST] m3 …") ถูก rollback เสมอ

create temp table if not exists m3_results (n int, test text, result text);
truncate m3_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today constant date := (now() at time zone 'Asia/Bangkok')::date;
  tag   constant text := '[TEST] m3 ' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  comp uuid;
  card_ontime uuid; card_late uuid; card_partial uuid; card_unpaid uuid;
  res text[] := '{}';
  v record;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;

  begin  -- rollback ตอนจบ (raise 'm3_undo')
    perform set_config('request.jwt.claims', json_build_object('sub', sales_id, 'role', 'authenticated')::text, true);
    set local role authenticated;

    insert into public.companies (name) values (tag) returning id into comp;

    -- จ่ายครบก่อนวันครบกำหนดจริง 2 วัน, วันเครดิตครบ = today - 10 (จ่ายช้ากว่าเครดิต 8 วัน)
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp, date '2000-01-01', 1000, 30, today - 40, today - 40, today)
    returning id into card_ontime;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_ontime, 400, 'transfer', today - 5, '10:00'),
           (card_ontime, 600, 'cheque',   today - 2, '10:00');

    -- จ่ายครบช้ากว่าวันครบกำหนดจริง 3 วัน
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp, date '2000-02-01', 500, 30, today - 30, today - 30, today - 4)
    returning id into card_late;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_late, 500, 'transfer', today - 1, '10:00');

    -- จ่ายบางส่วน / ยังไม่จ่าย
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp, date '2000-03-01', 500, 30, today, today, today + 5)
    returning id into card_partial;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_partial, 100, 'transfer', today, '10:00');
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp, date '2000-04-01', 500, 30, today, today, today + 5)
    returning id into card_unpaid;
    reset role;

    -- อ่านในนาม owner (ใช้ RLS ของ owner)
    perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
    set local role authenticated;

    select * into v from public.receivable_summary where id = card_ontime;
    res := res || array['1', 'จ่ายครบก่อนวันจริง 2 วัน → paid_late_actual_days = -2, paid_late_credit_days = 8 (owner อ่าน)',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.is_paid and v.paid_in_full_date = today - 2
         and v.paid_late_actual_days = -2 and v.paid_late_credit_days = 8 then 'PASS'
        else format('FAIL (is_paid=%s paid_in_full=%s actual=%s credit=%s)',
                    v.is_paid, v.paid_in_full_date, v.paid_late_actual_days, v.paid_late_credit_days)
      end];

    select * into v from public.receivable_summary where id = card_late;
    res := res || array['2', 'จ่ายครบช้ากว่าวันจริง 3 วัน → paid_late_actual_days = 3',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.paid_late_actual_days = 3 then 'PASS'
        else format('FAIL (actual=%s)', v.paid_late_actual_days)
      end];

    select * into v from public.receivable_summary where id = card_partial;
    res := res || array['3', 'จ่ายบางส่วน → ทั้ง 2 ช่องว่าง',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.paid_late_actual_days is null and v.paid_late_credit_days is null then 'PASS'
        else format('FAIL (actual=%s credit=%s)', v.paid_late_actual_days, v.paid_late_credit_days)
      end];

    select * into v from public.receivable_summary where id = card_unpaid;
    res := res || array['4', 'ยังไม่จ่าย → ทั้ง 2 ช่องว่าง, คอลัมน์เดิมยังถูก (balance 500, money_pct 0)',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.paid_late_actual_days is null and v.paid_late_credit_days is null
         and v.balance = 500 and v.money_pct = 0 then 'PASS'
        else format('FAIL (actual=%s credit=%s balance=%s)', v.paid_late_actual_days, v.paid_late_credit_days, v.balance)
      end];
    reset role;

    -- view ยังใช้ RLS ของคนอ่าน (security_invoker หลัง create or replace)
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    begin
      perform 1 from public.receivable_summary limit 1;
      res := res || array['5', 'anon อ่าน receivable_summary → ถูกปฏิเสธ',
        case when found then 'FAIL (อ่านได้)' else 'PASS (0 แถว)' end];
    exception when insufficient_privilege then
      res := res || array['5', 'anon อ่าน receivable_summary → ถูกปฏิเสธ', 'PASS (permission denied)'];
    end;
    reset role;

    raise exception 'm3_undo';
  exception when raise_exception then
    if sqlerrm <> 'm3_undo' then raise; end if;
  end;
  reset role;

  insert into m3_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

select n, test, result from m3_results order by n;
