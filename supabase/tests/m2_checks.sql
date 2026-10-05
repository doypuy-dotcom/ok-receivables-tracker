-- m2_checks.sql — ตรวจตาราง, RLS, trigger และ view ของ M2 แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 002_core_tables.sql)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบ (บริษัท "[TEST] m2 …") และทุกการเขียนที่ทดลองถูก rollback เสมอ
-- [แผน N] = ข้อทดสอบ N ของ M2 ใน implementation-plan.md, [+] = ข้อตรวจเพิ่ม

create temp table if not exists m2_results (n int, test text, result text);
truncate m2_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today      constant date := (now() at time zone 'Asia/Bangkok')::date;
  this_month constant date := date_trunc('month', (now() at time zone 'Asia/Bangkok'))::date;
  tag        constant text := '[TEST] m2 ' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  owner_claims text;
  sales_claims text;
  comp_a uuid; comp_b uuid; comp_c uuid; comp_d uuid;
  card1 uuid; card2 uuid; card3 uuid; card4 uuid; card5 uuid;
  pay1 uuid; pay2 uuid;
  res text[] := '{}';
  w record;
  v record;
  outcome text;
  err_constraint text;
  n_rows int;
  n_audit int;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;
  owner_claims := json_build_object('sub', owner_id, 'role', 'authenticated')::text;
  sales_claims := json_build_object('sub', sales_id, 'role', 'authenticated')::text;

  begin  -- ทุกอย่างใน block นี้ถูก rollback ตอนจบ (raise 'm2_undo')

    -- -----------------------------------------------------------------------
    -- เตรียมข้อมูล (sales)
    --   card1: บ.A ยอด 10,000 จ่ายแล้ว 6,000 (pay1)
    --   card2: บ.B ยอด  2,000 จ่ายแล้ว   500 (pay2)
    --   card3: บ.C ยอด  5,000 วันครบกำหนดจริง = เมื่อวาน (เวลาไทย) ยังไม่จ่าย
    --   card4: บ.D ยอด  1,000 (จะถูกยกเลิกในข้อ 5)
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;

    insert into public.companies (name) values (tag || ' A') returning id into comp_a;
    insert into public.companies (name) values (tag || ' B') returning id into comp_b;
    insert into public.companies (name) values (tag || ' C') returning id into comp_c;
    insert into public.companies (name) values (tag || ' D') returning id into comp_d;

    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, this_month, 10000, 30, today, today, today + 30) returning id into card1;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_b, this_month, 2000, 30, today, today, today + 30) returning id into card2;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_c, this_month, 5000, 30, today - 31, today - 31, today - 1) returning id into card3;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_d, this_month, 1000, 30, today, today, today + 30) returning id into card4;

    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card1, 6000, 'transfer', today, '10:00') returning id into pay1;
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card2, 500, 'transfer', today, '10:00') returning id into pay2;

    -- -----------------------------------------------------------------------
    -- 1–7: ข้อที่ต้องเปลี่ยนข้อมูลต่อเนื่องกัน (sales)
    -- -----------------------------------------------------------------------

    -- 1
    select balance, paid_amount, money_pct into v from public.receivable_summary where id = card2;
    res := res || array['1', '[แผน 4] ยอดรวม 2,000 จ่าย 500 → view: balance = 1,500 (paid 500, money_pct 25)',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.balance = 1500 and v.paid_amount = 500 and v.money_pct = 25 then 'PASS'
        else format('FAIL (balance=%s paid=%s money_pct=%s)', v.balance, v.paid_amount, v.money_pct)
      end];

    -- 2
    update public.payments set amount = 700 where id = pay2;
    select count(*) into n_audit
    from public.audit_logs where table_name = 'payments' and record_id = pay2 and action = 'update';
    select * into v
    from public.audit_logs where table_name = 'payments' and record_id = pay2 and action = 'update';
    res := res || array['2', '[แผน 6] แก้ยอดการจ่าย 500 → 700 → audit_logs: old 500, new 700, receivable_id, user_id ถูก',
      case
        when n_audit <> 1 then 'FAIL (พบแถว update ' || n_audit || ' แถว)'
        when (v.old_value ->> 'amount')::numeric = 500
         and (v.new_value ->> 'amount')::numeric = 700
         and v.receivable_id = card2
         and v.user_id = sales_id then 'PASS'
        else format('FAIL (old=%s new=%s receivable_id=%s user_id=%s)',
                    v.old_value ->> 'amount', v.new_value ->> 'amount', v.receivable_id, v.user_id)
      end];

    -- 3
    select days_to_actual_due, is_paid into v from public.receivable_summary where id = card3;
    res := res || array['3', '[แผน 8] actual_due_date = เมื่อวาน (เวลาไทย), ยังไม่จ่ายครบ → days_to_actual_due = -1',
      case
        when not found then 'FAIL (ไม่พบการ์ดใน view)'
        when v.days_to_actual_due = -1 and not v.is_paid then 'PASS'
        else format('FAIL (days_to_actual_due=%s is_paid=%s)', v.days_to_actual_due, v.is_paid)
      end];

    -- 4
    begin
      insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
      values (comp_d, this_month, 500, 30, today, today, today + 30);
      outcome := 'FAIL (บันทึกได้)';
      raise exception 'm2_undo';
    exception
      when unique_violation then outcome := 'PASS (unique_violation)';
      when raise_exception then
        if sqlerrm <> 'm2_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
      when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    res := res || array['4', '[แผน 5] สร้างการ์ดซ้ำ บริษัทเดิม เดือนเดิม → ปฏิเสธ', outcome];

    -- 5
    update public.receivables set is_cancelled = true where id = card4;
    select count(*) into n_audit
    from public.audit_logs
    where table_name = 'receivables' and record_id = card4 and action = 'cancel'
      and receivable_id = card4 and user_id = sales_id;
    res := res || array['5', '[แผน 5] ยกเลิกการ์ดแรก → audit_logs action = cancel',
      case when n_audit = 1 then 'PASS' else 'FAIL (พบ ' || n_audit || ' แถว)' end];

    -- 6
    begin
      insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
      values (comp_d, this_month, 1000, 30, today, today, today + 30) returning id into card5;
      outcome := 'PASS';
    exception when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    res := res || array['6', '[แผน 5] หลังยกเลิกการ์ดแรก สร้างใหม่ บริษัทเดิม เดือนเดิม → ผ่าน', outcome];

    -- 7
    insert into public.companies (name, created_at, created_by, updated_by)
    values (tag || ' E', '2000-01-01', owner_id, owner_id)
    returning created_at, created_by, updated_by into v;
    res := res || array['7', '[+] created_* / updated_by ถูกใส่อัตโนมัติ (ส่งค่าปลอมมา → ได้ผู้ใช้จริง + now())',
      case
        when v.created_by = sales_id and v.updated_by = sales_id and v.created_at = now() then 'PASS'
        else format('FAIL (created_by=%s updated_by=%s created_at=%s)', v.created_by, v.updated_by, v.created_at)
      end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 8: owner อ่านได้
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.receivable_summary where company_name like tag || '%';
    select count(*) into n_audit from public.audit_logs where receivable_id = card1;
    res := res || array['8', '[+] owner: อ่าน view เห็นการ์ดทดสอบ 4 ใบ (ไม่รวมใบที่ยกเลิก) และอ่าน audit_logs ได้',
      case when n_rows = 4 and n_audit > 0 then 'PASS'
           else format('FAIL (view %s ใบ, audit %s แถว)', n_rows, n_audit) end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 9–37: ลองเขียนทีละคำสั่ง แต่ละคำสั่งถูก rollback ทันที
    --   expect: ok      = ต้องสำเร็จ (>= 1 แถว)
    --           denied  = ต้องถูก RLS / สิทธิ์ปฏิเสธ (permission denied หรือ 0 แถว)
    --           <sqlstate>[:<name>] = ต้อง error ด้วยรหัสนี้ (และข้อความ หรือชื่อ constraint = name)
    --   who: none = role postgres ไม่มี JWT (เหมือนรันใน SQL Editor / service ที่ไม่มีผู้ใช้)
    -- -----------------------------------------------------------------------
    for w in
      select * from (values
        (9,  '[แผน 1] owner: insert payments', 'owner',
             format('insert into public.payments (receivable_id, amount, method, paid_date, paid_time) values (%L, 100, %L, %L, %L)', card1, 'transfer', today, '10:00'),
             'denied'),
        (10, '[แผน 2] sales: DELETE companies', 'sales',
             format('delete from public.companies where id = %L', comp_a), 'denied'),
        (11, '[แผน 2] sales: DELETE receivables', 'sales',
             format('delete from public.receivables where id = %L', card1), 'denied'),
        (12, '[แผน 2] sales: DELETE payments', 'sales',
             format('delete from public.payments where id = %L', pay1), 'denied'),
        (13, '[แผน 2] sales: DELETE audit_logs', 'sales',
             format('delete from public.audit_logs where receivable_id = %L', card1), 'denied'),
        (14, '[แผน 3] ยอดรวม 10,000 จ่ายแล้ว 6,000 จ่ายอีก 5,000 → ปฏิเสธ', 'sales',
             format('insert into public.payments (receivable_id, amount, method, paid_date, paid_time) values (%L, 5000, %L, %L, %L)', card1, 'cheque', today, '11:00'),
             '23514:payments_exceed_total'),
        (15, '[+] จ่ายอีก 4,000 (ครบพอดี 10,000) → ผ่าน', 'sales',
             format('insert into public.payments (receivable_id, amount, method, paid_date, paid_time) values (%L, 4000, %L, %L, %L)', card1, 'cheque', today, '11:00'),
             'ok'),
        (16, '[+] แก้การจ่าย 6,000 → 10,000 (ไม่นับยอดเดิมของตัวเอง) → ผ่าน', 'sales',
             format('update public.payments set amount = 10000 where id = %L', pay1), 'ok'),
        (17, '[+] แก้การจ่าย 6,000 → 10,000.01 → ปฏิเสธ', 'sales',
             format('update public.payments set amount = 10000.01 where id = %L', pay1), '23514:payments_exceed_total'),
        (18, '[+] แก้ total_amount 10,000 → 5,999.99 (จ่ายแล้ว 6,000) → ปฏิเสธ', 'sales',
             format('update public.receivables set total_amount = 5999.99 where id = %L', card1), '23514:total_below_paid'),
        (19, '[+] แก้ total_amount 10,000 → 6,000 (เท่ากับที่จ่ายแล้ว) → ผ่าน', 'sales',
             format('update public.receivables set total_amount = 6000 where id = %L', card1), 'ok'),
        (20, '[+] เพิ่มการจ่ายในการ์ดที่ยกเลิก → ปฏิเสธ', 'sales',
             format('insert into public.payments (receivable_id, amount, method, paid_date, paid_time) values (%L, 100, %L, %L, %L)', card4, 'transfer', today, '10:00'),
             '23514:receivable_cancelled'),
        (21, '[แผน 7] sales: แก้ audit_logs', 'sales',
             format('update public.audit_logs set action = %L where receivable_id = %L', 'update', card1), 'denied'),
        (22, '[แผน 7] owner: ลบ audit_logs', 'owner',
             format('delete from public.audit_logs where receivable_id = %L', card1), 'denied'),
        (23, '[+] sales: insert audit_logs เอง', 'sales',
             format('insert into public.audit_logs (user_id, action, table_name, record_id, new_value) values (%L, %L, %L, %L, %L)', sales_id, 'create', 'companies', comp_a, '{}'),
             'denied'),
        (24, '[+] owner: insert companies', 'owner',
             format('insert into public.companies (name) values (%L)', tag || ' X'), 'denied'),
        (25, '[+] owner: insert receivables', 'owner',
             format('insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date) values (%L, %L, 1000, 30, %L, %L, %L)',
                    comp_b, (this_month - interval '1 month')::date, today, today, today + 30),
             'denied'),
        (26, '[+] owner: แก้ companies', 'owner',
             format('update public.companies set name = %L where id = %L', tag || ' X', comp_a), 'denied'),
        (27, '[+] owner: แก้ receivables', 'owner',
             format('update public.receivables set total_amount = 1 where id = %L', card2), 'denied'),
        (28, '[+] owner: แก้ payments', 'owner',
             format('update public.payments set amount = 1 where id = %L', pay2), 'denied'),
        (29, '[+] ไม่มีผู้ใช้ล็อกอิน: insert companies → ปฏิเสธ', 'none',
             format('insert into public.companies (name) values (%L)', tag || ' X'), '42501:not_authenticated'),
        (30, '[+] ไม่มีผู้ใช้ล็อกอิน: แก้ payments → ปฏิเสธ', 'none',
             format('update public.payments set amount = 1 where id = %L', pay1), '42501:not_authenticated'),
        (31, '[+] ชื่อบริษัทว่าง → ปฏิเสธ', 'sales',
             format('insert into public.companies (name) values (%L)', ''), '23514:companies_name_trimmed'),
        (32, '[+] ชื่อบริษัทมีแต่ช่องว่าง → ปฏิเสธ', 'sales',
             format('insert into public.companies (name) values (%L)', '   '), '23514:companies_name_trimmed'),
        (33, '[+] ชื่อบริษัทมีช่องว่างหน้า → ปฏิเสธ', 'sales',
             format('insert into public.companies (name) values (%L)', ' ' || tag || ' X'), '23514:companies_name_trimmed'),
        (34, '[+] แก้ชื่อบริษัทให้มีช่องว่างหลัง → ปฏิเสธ', 'sales',
             format('update public.companies set name = %L where id = %L', tag || ' A ', comp_a), '23514:companies_name_trimmed'),
        (35, '[+] ชื่อบริษัทมีช่องว่างตรงกลาง → ผ่าน', 'sales',
             format('insert into public.companies (name) values (%L)', tag || ' X 1'), 'ok'),
        (36, '[+] ย้ายการจ่ายไปการ์ดอื่น (เปลี่ยน receivable_id) → ปฏิเสธ', 'sales',
             format('update public.payments set receivable_id = %L where id = %L', card2, pay1), '23514:payment_receivable_immutable'),
        (37, '[+] แก้การจ่ายโดยส่ง receivable_id เดิมมาด้วย → ผ่าน', 'sales',
             format('update public.payments set receivable_id = %L, paid_time = %L where id = %L', card1, '12:00', pay1), 'ok')
      ) t(n, label, who, stmt, expect)
    loop
      perform set_config('request.jwt.claims',
        case w.who when 'owner' then owner_claims when 'sales' then sales_claims else '{}' end, true);
      if w.who <> 'none' then
        set local role authenticated;
      end if;
      begin
        execute w.stmt;
        get diagnostics n_rows = row_count;
        outcome := case
          when w.expect = 'ok' and n_rows > 0 then 'PASS'
          when w.expect = 'denied' and n_rows = 0 then 'PASS (0 แถว)'
          when n_rows = 0 then 'FAIL (0 แถว)'
          else 'FAIL (สำเร็จ ' || n_rows || ' แถว)'
        end;
        raise exception 'm2_undo';  -- rollback สิ่งที่อาจถูกเปลี่ยน
      exception
        when raise_exception then
          if sqlerrm <> 'm2_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
        when others then
          get stacked diagnostics err_constraint = constraint_name;
          outcome := case
            when w.expect = 'denied' and sqlstate = '42501' then 'PASS (permission denied)'
            when w.expect in (sqlstate, sqlstate || ':' || sqlerrm) then 'PASS (' || sqlerrm || ')'
            when w.expect = sqlstate || ':' || err_constraint then 'PASS (' || err_constraint || ')'
            else 'FAIL (' || sqlstate || ' ' || sqlerrm || ')'
          end;
      end;
      reset role;
      res := res || array[w.n::text, w.label, outcome];
    end loop;

    -- -----------------------------------------------------------------------
    -- 38: ไม่ได้ล็อกอิน (anon) อ่าน view
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    begin
      select count(*) into n_rows from public.receivable_summary;
      outcome := case when n_rows = 0 then 'PASS (0 แถว)' else 'FAIL (' || n_rows || ' แถว)' end;
    exception when insufficient_privilege then outcome := 'PASS (permission denied)';
    end;
    reset role;
    res := res || array['38', '[+] anon: อ่าน receivable_summary', outcome];

    -- -----------------------------------------------------------------------
    -- 39: sales ที่ is_active = false (rollback ตอนจบ)
    --     อ่าน view ได้ 0 แถว = view ใช้ RLS ของคนอ่านจริง (security_invoker)
    -- -----------------------------------------------------------------------
    update public.profiles set is_active = false where id = sales_id;
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.receivable_summary;
    begin
      insert into public.companies (name) values (tag || ' F');
      outcome := 'FAIL (บันทึกได้)';
      raise exception 'm2_undo';
    exception
      when insufficient_privilege then outcome := 'PASS';
      when raise_exception then
        if sqlerrm <> 'm2_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
      when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    reset role;
    res := res || array['39', '[+] sales is_active = false: อ่าน view ได้ 0 แถว และ insert companies ไม่ได้',
      case when n_rows = 0 then outcome else 'FAIL (อ่าน view ได้ ' || n_rows || ' แถว)' end];

    raise exception 'm2_undo';
  exception when raise_exception then
    if sqlerrm <> 'm2_undo' then raise; end if;
  end;
  reset role;

  insert into m2_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

select n, test, result from m2_results order by n;
