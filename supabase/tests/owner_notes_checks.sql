-- owner_notes_checks.sql — ตรวจ "เจ้าของเขียนหมายเหตุได้" (V2 ข้อ 2 · migration 007_owner_notes.sql)
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 007)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบ (บริษัท "[TEST] notes …") และทุกการเขียนถูก rollback เสมอ
-- **ผลทุกข้อออกมาใน result set เดียวที่ท้ายไฟล์** (SQL Editor แสดงเฉพาะชุดสุดท้าย):
--   ข้อ 0 = แถวสรุป "PASS x / y ข้อ" + ALL PASS หรือ HAS FAIL · ข้อ 1–25 = ผลแต่ละข้อ
--
-- [สั่ง N] = ข้อที่สั่งให้ตรวจ, [+] = ข้อตรวจเพิ่ม
--   สั่ง 1 เจ้าของ insert หมายเหตุได้ (และฝ่ายขายยังได้)        → ข้อ 1, 2, 3, 4, 20, 21
--   สั่ง 2 เจ้าของ update / delete หมายเหตุไม่ได้                → ข้อ 5, 6, 7, 8, 23, 24
--   สั่ง 3 เจ้าของยังเขียน receivables / payments / companies ไม่ได้ → ข้อ 9–14
--   สั่ง 4 บัญชี is_active = false เขียนไม่ได้                   → ข้อ 15, 16, 17
--   สั่ง 5 audit / realtime ของหมายเหตุทำงานเหมือนเดิม           → ข้อ 22, 25
--   [+] กฎเดิมของ 005 ยังบังคับกับเจ้าของด้วย                   → ข้อ 18, 19
--
-- ข้อมูลทดสอบ (ฝ่ายขายสร้าง): 2 บริษัท · การ์ดปกติ 1 ใบ (มีการจ่าย 1 รายการ) ·
--   การ์ดที่ถูกยกเลิก 1 ใบ · การ์ดที่มีแต่หมายเหตุของเจ้าของ 1 ใบ (ใช้ในข้อ 21)

create temp table if not exists notes_results (n int, test text, result text);
truncate notes_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today      constant date := (now() at time zone 'Asia/Bangkok')::date;
  this_month constant date := date_trunc('month', (now() at time zone 'Asia/Bangkok'))::date;
  prev_month constant date := (date_trunc('month', (now() at time zone 'Asia/Bangkok')) - interval '1 month')::date;
  tag        constant text := '[TEST] notes ' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  owner_claims text;
  sales_claims text;
  comp_a uuid; comp_b uuid;
  card_a uuid; card_dead uuid; card_c uuid;
  pay_a uuid;
  note_sales uuid; note_owner uuid; note_sales2 uuid;
  res text[] := '{}';
  v record;
  w record;
  outcome text;
  err_constraint text;
  n_rows int;
  n_rows2 int;
  n_audit_before int;
  n_audit_after int;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;
  owner_claims := json_build_object('sub', owner_id, 'role', 'authenticated')::text;
  sales_claims := json_build_object('sub', sales_id, 'role', 'authenticated')::text;

  begin  -- ทุกอย่างใน block นี้ถูก rollback ตอนจบ (raise 'notes_undo')

    -- =======================================================================
    -- เตรียมข้อมูล (ฝ่ายขายสร้างบริษัท / การ์ด / การจ่าย ผ่าน RLS + trigger จริง)
    -- =======================================================================
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;

    insert into public.companies (name) values (tag || ' a') returning id into comp_a;
    insert into public.companies (name) values (tag || ' b') returning id into comp_b;

    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, this_month, 10000, 30, today, today, today + 30) returning id into card_a;
    -- การจ่าย 1 รายการ: ข้อ 12 ("เจ้าของแก้การจ่าย") จะได้ 0 แถวเพราะ RLS จริง ๆ ไม่ใช่เพราะไม่มีแถว
    insert into public.payments (receivable_id, amount, method, paid_date, paid_time)
    values (card_a, 1000, 'transfer', today, '09:00') returning id into pay_a;

    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_b, this_month, 5000, 30, today, today, today + 30) returning id into card_dead;
    update public.receivables set is_cancelled = true where id = card_dead;

    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, prev_month, 2000, 30, today, today, today + 30) returning id into card_c;

    -- หมายเหตุของฝ่ายขาย (ของเดิมต้องยังเขียนได้)
    insert into public.receivable_notes (receivable_id, body)
    values (card_a, 'ฝ่ายขาย: โทรทวงแล้ว ลูกค้าขอเลื่อนเป็นวันที่ 25') returning id into note_sales;

    reset role;

    -- =======================================================================
    -- 1–2: เจ้าของเขียนหมายเหตุได้ และ created_by มาจาก trigger ไม่ใช่ค่าที่แอปส่งมา
    -- =======================================================================
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    begin
      -- ส่ง created_by เป็นของฝ่ายขายมาด้วย: trigger ต้องเขียนทับเป็น auth.uid() ของเจ้าของ
      insert into public.receivable_notes (receivable_id, body, created_by)
      values (card_a, 'เจ้าของ: ช่วยโทรตามบริษัทนี้ให้ด้วย ยอดค้างนานแล้ว', sales_id)
      returning id into note_owner;
      outcome := 'PASS';
    exception when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    reset role;
    res := res || array['1', '[สั่ง 1] เจ้าของเขียนหมายเหตุในการ์ดได้', outcome];

    select n.created_by into v from public.receivable_notes n where n.id = note_owner;
    res := res || array['2', '[+] created_by ของหมายเหตุนั้นเป็นเจ้าของ (trigger set_note_meta เขียนทับค่าที่ส่งมา)',
      case when v.created_by = owner_id then 'PASS'
           when v.created_by = sales_id then 'FAIL (ใช้ค่าที่แอปส่งมา)'
           else 'FAIL (ไม่พบแถว)' end];

    -- =======================================================================
    -- 3: ฝ่ายขายยังเขียนได้เหมือนเดิม (007 ขยายสิทธิ์ ไม่ใช่ย้ายสิทธิ์)
    -- =======================================================================
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    begin
      insert into public.receivable_notes (receivable_id, body)
      values (card_a, 'ฝ่ายขาย: รับทราบครับ จะโทรวันนี้') returning id into note_sales2;
      outcome := 'PASS';
    exception when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    reset role;
    res := res || array['3', '[สั่ง 1] ฝ่ายขายยังเขียนหมายเหตุได้เหมือนเดิม', outcome];

    -- =======================================================================
    -- 4: ทั้ง 2 ฝ่ายอ่านหมายเหตุของกันได้ (เจ้าของเห็นคำตอบของฝ่ายขาย และกลับกัน)
    -- =======================================================================
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.receivable_notes where receivable_id = card_a;
    reset role;
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    select count(*) into n_rows2 from public.receivable_notes where receivable_id = card_a;
    reset role;
    res := res || array['4', '[สั่ง 1] เจ้าของและฝ่ายขายอ่านหมายเหตุของกันได้ (เห็น 3 รายการทั้งคู่)',
      case when n_rows = 3 and n_rows2 = 3 then 'PASS'
           else format('FAIL (เจ้าของเห็น %s, ฝ่ายขายเห็น %s)', n_rows, n_rows2) end];

    -- =======================================================================
    -- 5–19: ลองเขียนทีละคำสั่ง แต่ละคำสั่งถูก rollback ทันที (ผลของข้ออื่นไม่เพี้ยน)
    --   expect: ok = ต้องสำเร็จ · denied = ต้องถูกปฏิเสธ (42501 หรือ 0 แถว)
    --           <sqlstate>[:<ชื่อ>] = ต้อง error ด้วยรหัสนั้น (และข้อความ หรือชื่อ constraint)
    --   who: inactive_owner / inactive_sales = ปิดบัญชีก่อนลองแล้วเปิดคืน · anon = ไม่ล็อกอิน
    -- =======================================================================
    for w in
      select * from (values
        (5,  '[สั่ง 2] เจ้าของแก้หมายเหตุของตัวเอง', 'owner',
             format('update public.receivable_notes set body = %L where id = %L', 'แก้ข้อความ', note_owner), 'denied'),
        (6,  '[สั่ง 2] เจ้าของลบหมายเหตุของตัวเอง', 'owner',
             format('delete from public.receivable_notes where id = %L', note_owner), 'denied'),
        (7,  '[+] ฝ่ายขายแก้หมายเหตุ (ของเดิมก็ห้ามอยู่แล้ว)', 'sales',
             format('update public.receivable_notes set body = %L where id = %L', 'แก้ข้อความ', note_sales), 'denied'),
        (8,  '[+] ฝ่ายขายลบหมายเหตุ', 'sales',
             format('delete from public.receivable_notes where id = %L', note_sales), 'denied'),
        (9,  '[สั่ง 3] เจ้าของเพิ่มการ์ดยอดค้าง', 'owner',
             format('insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date) values (%L, %L, 1000, 30, %L, %L, %L)',
                    comp_b, prev_month, today, today, today + 30), 'denied'),
        (10, '[สั่ง 3] เจ้าของแก้การ์ดยอดค้าง', 'owner',
             format('update public.receivables set total_amount = 1 where id = %L', card_a), 'denied'),
        (11, '[สั่ง 3] เจ้าของเพิ่มการจ่าย', 'owner',
             format('insert into public.payments (receivable_id, amount, method, paid_date, paid_time) values (%L, 100, %L, %L, %L)',
                    card_a, 'transfer', today, '10:00'), 'denied'),
        (12, '[สั่ง 3] เจ้าของแก้การจ่ายที่มีอยู่จริง', 'owner',
             format('update public.payments set amount = 1 where id = %L', pay_a), 'denied'),
        (13, '[สั่ง 3] เจ้าของเพิ่มบริษัท', 'owner',
             format('insert into public.companies (name) values (%L)', tag || ' x'), 'denied'),
        (14, '[สั่ง 3] เจ้าของแก้ชื่อบริษัท', 'owner',
             format('update public.companies set name = %L where id = %L', tag || ' y', comp_a), 'denied'),
        (15, '[สั่ง 4] เจ้าของที่ is_active = false เขียนหมายเหตุ', 'inactive_owner',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)',
                    card_a, 'บัญชีถูกปิดแล้วไม่ควรเขียนได้'), 'denied'),
        (16, '[สั่ง 4] ฝ่ายขายที่ is_active = false เขียนหมายเหตุ', 'inactive_sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)',
                    card_a, 'บัญชีถูกปิดแล้วไม่ควรเขียนได้'), 'denied'),
        (17, '[สั่ง 4] ไม่ได้ล็อกอิน (anon) เขียนหมายเหตุ', 'anon',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)',
                    card_a, 'anon ไม่ควรเขียนได้'), 'denied'),
        (18, '[+] เจ้าของเขียนหมายเหตุในการ์ดที่ถูกยกเลิก → ปฏิเสธ (กฎเดิมของ 005)', 'owner',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)',
                    card_dead, 'การ์ดนี้ถูกยกเลิกแล้ว'), '23514:note_receivable_cancelled'),
        (19, '[+] เจ้าของเขียนหมายเหตุที่มีแต่ช่องว่าง → ปฏิเสธ (constraint เดิม)', 'owner',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)',
                    card_a, '   '), '23514:receivable_notes_body_trimmed')
      ) t(n, label, who, stmt, expect)
    loop
      -- ปิดบัญชีชั่วคราวในนาม role ของ SQL Editor (profiles แก้ได้จากที่นี่เท่านั้น — schema.md 3.1)
      if w.who = 'inactive_owner' then
        update public.profiles set is_active = false where id = owner_id;
      elsif w.who = 'inactive_sales' then
        update public.profiles set is_active = false where id = sales_id;
      end if;

      perform set_config('request.jwt.claims',
        case w.who
          when 'owner'          then owner_claims
          when 'inactive_owner' then owner_claims
          when 'sales'          then sales_claims
          when 'inactive_sales' then sales_claims
          else '{"role":"anon"}'
        end, true);
      if w.who = 'anon' then
        set local role anon;
      else
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
        raise exception 'notes_undo';  -- rollback สิ่งที่อาจถูกเปลี่ยน
      exception
        when raise_exception then
          if sqlerrm <> 'notes_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
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

      if w.who = 'inactive_owner' then
        update public.profiles set is_active = true where id = owner_id;
      elsif w.who = 'inactive_sales' then
        update public.profiles set is_active = true where id = sales_id;
      end if;

      res := res || array[w.n::text, w.label, outcome];
    end loop;

    -- =======================================================================
    -- 20–21: view receivable_latest_note — รายการล่าสุด + ใครเขียน (created_by_role ใหม่ใน 007)
    --   now() ภายใน transaction เดียวเท่ากันทุกแถว จึงไม่ใช่เวลาจริงของการเขียนแต่ละครั้ง
    --   → ตั้ง created_at ของ 2 รายการแรกให้ย้อนหลังในนาม role ของ SQL Editor
    --     เพื่อให้ "รายการล่าสุด" มีคำตอบเดียวแน่นอน (ของจริงแต่ละครั้งเป็น transaction ของตัวเอง)
    -- =======================================================================
    update public.receivable_notes set created_at = now() - interval '2 hours' where id = note_sales;
    update public.receivable_notes set created_at = now() - interval '1 hour'  where id = note_owner;

    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    select * into v from public.receivable_latest_note where receivable_id = card_a;
    reset role;
    res := res || array['20', '[สั่ง 1] หมายเหตุล่าสุดของการ์ด = รายการที่เขียนล่าสุด (ของฝ่ายขาย) · created_by_role = sales',
      case when v.note_id = note_sales2 and v.created_by = sales_id and v.created_by_role = 'sales'
           then 'PASS'
           else format('FAIL (role %s, ล่าสุดตรงกับที่คาด %s)',
                       v.created_by_role, v.note_id = note_sales2) end];

    -- การ์ดที่มีแต่หมายเหตุของเจ้าของ → การ์ดในหน้าตารางต้องทำสีให้เด่นและติดป้าย "เจ้าของ"
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    insert into public.receivable_notes (receivable_id, body)
    values (card_c, 'เจ้าของ: ขอยอดอัปเดตของบริษัทนี้ด้วยครับ');
    select * into v from public.receivable_latest_note where receivable_id = card_c;
    reset role;
    res := res || array['21', '[สั่ง 1] การ์ดที่หมายเหตุล่าสุดเป็นของเจ้าของ → created_by_role = owner',
      case when v.created_by = owner_id and v.created_by_role = 'owner'
           then 'PASS' else format('FAIL (role %s)', v.created_by_role) end];

    -- =======================================================================
    -- 22: หมายเหตุไม่ถูกบันทึกลง audit_logs (ตามเจตนา — ตารางต่อท้ายอย่างเดียว schema.md 3.6)
    -- =======================================================================
    select count(*) into n_audit_before from public.audit_logs where receivable_id = card_a;
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    insert into public.receivable_notes (receivable_id, body) values (card_a, 'เจ้าของ: ทดสอบ audit');
    reset role;
    select count(*) into n_audit_after from public.audit_logs where receivable_id = card_a;
    res := res || array['22', '[สั่ง 5] เขียนหมายเหตุแล้วไม่มีแถวใหม่ใน audit_logs (ตัวตารางเป็นประวัติในตัว)',
      case when n_audit_after = n_audit_before then 'PASS'
           else format('FAIL (เพิ่มขึ้น %s แถว)', n_audit_after - n_audit_before) end];

    raise exception 'notes_undo';
  exception when raise_exception then
    if sqlerrm <> 'notes_undo' then raise; end if;
  end;
  reset role;

  -- ตัวแปรของ PL/pgSQL ไม่ถูก rollback ไปกับ block ด้านบน จึงเก็บผลลง temp table ตรงนี้
  insert into notes_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

-- ---------------------------------------------------------------------------
-- 23–25: ตรวจโครงสร้าง (ไม่ต้องเขียนข้อมูล) — เก็บลง notes_results เหมือนข้อ 1–22
--   เพราะ Supabase SQL Editor แสดงเฉพาะ result set สุดท้ายของไฟล์
-- ---------------------------------------------------------------------------
insert into notes_results (n, test, result)
select
  23,
  '[สั่ง 2] policy ของ receivable_notes: insert ให้ผู้ใช้ที่ active ทุกคน · ไม่มี update / delete',
  case
    when exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'receivable_notes' and cmd in ('UPDATE', 'DELETE', 'ALL')
    ) then 'FAIL (มี policy แก้/ลบ)'
    when (
      select count(*) from pg_policies
      where schemaname = 'public' and tablename = 'receivable_notes' and cmd = 'INSERT'
        and with_check like '%my_role%' and with_check like '%IS NOT NULL%'
    ) <> 1 then 'FAIL (policy insert ไม่ตรง — ยังไม่ได้รัน 007?)'
    when exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'receivable_notes' and cmd = 'INSERT'
        and with_check like '%sales%'
    ) then 'FAIL (policy insert ยังจำกัดเป็น sales)'
    else 'PASS'
  end
union all
select
  24,
  '[สั่ง 2] สิทธิ์ระดับตาราง: authenticated ได้ select + insert เท่านั้น · anon ไม่ได้อะไรเลย',
  case
    when exists (
      select 1 from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'receivable_notes' and grantee = 'anon'
    ) then 'FAIL (anon มีสิทธิ์)'
    when (
      select coalesce(string_agg(distinct privilege_type, ',' order by privilege_type), '')
      from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'receivable_notes' and grantee = 'authenticated'
    ) <> 'INSERT,SELECT' then 'FAIL (สิทธิ์ไม่ตรง)'
    else 'PASS'
  end
union all
select
  25,
  '[สั่ง 5] realtime + trigger ของ receivable_notes เหมือนเดิม (ไม่มี trigger audit) · คอลัมน์ของ view ตรงกับ schema.md 4.1',
  case
    when not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'receivable_notes'
    ) then 'FAIL (ไม่อยู่ใน publication supabase_realtime)'
    when (
      select coalesce(string_agg(tgname, ',' order by tgname), '')
      from pg_trigger where tgrelid = 'public.receivable_notes'::regclass and not tgisinternal
    ) <> 'trg_10_set_meta,trg_20_check_rules' then 'FAIL (trigger เปลี่ยน)'
    when (
      select coalesce(string_agg(column_name, ',' order by ordinal_position), '')
      from information_schema.columns
      where table_schema = 'public' and table_name = 'receivable_latest_note'
    ) <> 'receivable_id,note_id,body,created_by,created_at,created_by_role'
      then 'FAIL (คอลัมน์ของ receivable_latest_note ไม่ตรง)'
    else 'PASS'
  end;

-- ---------------------------------------------------------------------------
-- ผลทั้งหมดใน result set เดียว: แถวสรุป (ข้อ 0) บนสุด แล้วข้อ 1–25 เรียงตามหมายเลข
-- ทุกผลที่ผ่านขึ้นต้นด้วย "PASS" จึงนับด้วย like 'PASS%' ได้ตรง ๆ
-- ---------------------------------------------------------------------------
with summary as (
  select count(*) filter (where result like 'PASS%') as passed, count(*) as total
  from notes_results
)
select 0                                                                  as n,
       format('สรุป: PASS %s / %s ข้อ', s.passed, s.total)                as test,
       case when s.passed = s.total then 'ALL PASS' else 'HAS FAIL' end   as result
from summary s
union all
select n, test, result from notes_results
order by n;
