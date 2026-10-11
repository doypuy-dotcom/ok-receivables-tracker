-- v1_checks.sql — ตรวจ receivable_notes + app_feedback ของ V1 รอบ ข แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 005_notes_and_feedback.sql)
-- ไม่เปลี่ยนข้อมูลจริง: ข้อมูลทดสอบ (บริษัท "[TEST] v1 …") และทุกการเขียนที่ทดลองถูก rollback เสมอ
-- [สั่ง N] = ข้อที่สั่งให้ตรวจใน V1 รอบ ข, [+] = ข้อตรวจเพิ่ม
--   สั่ง 1 = role ผิดเขียนไม่ได้        → ข้อ 10, 11, 12
--   สั่ง 2 = แก้/ลบไม่ได้               → ข้อ 13–20 และ 8 (ไม่มี policy UPDATE/DELETE เลย)
--   สั่ง 3 = อ่าน feedback คนอื่นไม่ได้  → ข้อ 5, 6
--   สั่ง 4 = การ์ดที่ยกเลิกเขียนหมายเหตุไม่ได้ → ข้อ 21

create temp table if not exists v1_results (n int, test text, result text);
truncate v1_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  today      constant date := (now() at time zone 'Asia/Bangkok')::date;
  this_month constant date := date_trunc('month', (now() at time zone 'Asia/Bangkok'))::date;
  tag        constant text := '[TEST] v1 ' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISS');
  owner_claims text;
  sales_claims text;
  comp_a uuid; comp_b uuid;
  card_open uuid; card_cancelled uuid;
  note1 uuid; note2 uuid;
  fb_sales uuid; fb_owner uuid;
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

  begin  -- ทุกอย่างใน block นี้ถูก rollback ตอนจบ (raise 'v1_undo')

    -- -----------------------------------------------------------------------
    -- เตรียมข้อมูล (sales)
    --   card_open      : การ์ดปกติ มีหมายเหตุ 2 รายการ
    --   card_cancelled : การ์ดที่ถูกยกเลิก (ใช้ในข้อ 21)
    --   fb_sales / fb_owner : feedback 1 แถวของแต่ละคน
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;

    insert into public.companies (name) values (tag || ' A') returning id into comp_a;
    insert into public.companies (name) values (tag || ' B') returning id into comp_b;

    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_a, this_month, 10000, 30, today, today, today + 30) returning id into card_open;
    insert into public.receivables (company_id, account_month, total_amount, credit_days, credit_start_date, actual_start_date, actual_due_date)
    values (comp_b, this_month, 5000, 30, today, today, today + 30) returning id into card_cancelled;
    update public.receivables set is_cancelled = true where id = card_cancelled;

    -- 1: sales เขียนหมายเหตุได้ และ created_by / created_at ถูกใส่อัตโนมัติ
    --    (ส่งค่าปลอมมา: ต้องถูกเขียนทับด้วยผู้ใช้จริงและ now())
    insert into public.receivable_notes (receivable_id, body, created_at, created_by)
    values (card_open, 'ลูกค้าขอเลื่อนจ่ายเป็นวันที่ 25', '2000-01-01', owner_id)
    returning id, created_by, created_at into v;
    note1 := v.id;
    res := res || array['1', '[+] sales: เขียนหมายเหตุได้ และ created_by / created_at ถูกใส่อัตโนมัติ (ส่งค่าปลอมมา → ได้ผู้ใช้จริง + now())',
      case
        when v.created_by = sales_id and v.created_at = now() then 'PASS'
        else format('FAIL (created_by=%s created_at=%s)', v.created_by, v.created_at)
      end];

    insert into public.receivable_notes (receivable_id, body)
    values (card_open, 'โอนมา 9,970 ขาด 30 บาท เพราะค่าธรรมเนียมธนาคาร')
    returning id into note2;

    -- 2: ไม่มีแถว audit_logs ของหมายเหตุ (ข้อยกเว้นที่ระบุไว้ — schema.md 3.6)
    select count(*) into n_audit from public.audit_logs where record_id in (note1, note2);
    res := res || array['2', '[+] หมายเหตุไม่เขียน audit_logs (ตารางเป็นประวัติในตัว — schema.md 3.6)',
      case when n_audit = 0 then 'PASS (0 แถว)' else 'FAIL (พบ ' || n_audit || ' แถว)' end];

    -- 3: view receivable_latest_note คืน 1 แถวต่อ 1 การ์ด
    --    ในทรานแซกชันเดียว now() เท่ากันทุกคำสั่ง → created_at ของ 2 หมายเหตุเท่ากันเป๊ะ
    --    จึงตรวจตัวตัดสินสำรอง (id มากสุด) ซึ่งเป็นสิ่งที่ทำให้ผลของ view คงที่
    select count(*) into n_rows from public.receivable_latest_note where receivable_id = card_open;
    select note_id, body into v from public.receivable_latest_note where receivable_id = card_open;
    res := res || array['3', '[+] view receivable_latest_note: 1 แถวต่อ 1 การ์ด และเลือกแถวได้คงที่เมื่อเวลาเท่ากัน',
      case
        when n_rows <> 1 then 'FAIL (' || n_rows || ' แถว)'
        when v.note_id = greatest(note1, note2) then 'PASS'
        else 'FAIL (เลือก note_id ผิด)'
      end];

    -- 4: การ์ดที่ยังไม่มีหมายเหตุไม่มีแถวใน view (การ์ดนั้นแสดงโดยไม่มีบรรทัดหมายเหตุ)
    select count(*) into n_rows from public.receivable_latest_note where receivable_id = card_cancelled;
    res := res || array['4', '[+] การ์ดที่ยังไม่มีหมายเหตุ → ไม่มีแถวใน receivable_latest_note',
      case when n_rows = 0 then 'PASS (0 แถว)' else 'FAIL (' || n_rows || ' แถว)' end];

    -- feedback ของ sales — ส่งค่าปลอมของ user_id / role / created_at มาด้วย ต้องถูกเขียนทับ
    insert into public.app_feedback (user_id, role, created_at, app_version, helpful, issues, sales_sheet_minutes)
    values (owner_id, 'owner', '2000-01-01', 'V1', 4, 'ขอช่องเลขเช็คด้วย', 10)
    returning id, user_id, role, created_at into v;
    fb_sales := v.id;
    res := res || array['5', '[+] sales: ส่ง feedback ได้ และ user_id / role / created_at ถูกใส่อัตโนมัติ (ส่งค่าปลอมมา → ได้ของจริง)',
      case
        when v.user_id = sales_id and v.role = 'sales' and v.created_at = now() then 'PASS'
        else format('FAIL (user_id=%s role=%s created_at=%s)', v.user_id, v.role, v.created_at)
      end];

    -- 6: sales อ่าน feedback ของตัวเองได้ 1 แถว
    select count(*) into n_rows from public.app_feedback;
    res := res || array['6', '[+] sales: อ่าน app_feedback เห็นแถวของตัวเอง',
      case when n_rows = 1 then 'PASS (1 แถว)' else 'FAIL (' || n_rows || ' แถว)' end];
    reset role;

    -- feedback ของ owner
    perform set_config('request.jwt.claims', owner_claims, true);
    set local role authenticated;
    insert into public.app_feedback (app_version, helpful, issues, owner_asks_per_week)
    values ('V1', 5, 'ดีขึ้นมาก', 0)
    returning id into fb_owner;

    -- 7: [สั่ง 3] owner อ่าน app_feedback เห็นแค่แถวของตัวเอง ไม่เห็นของ sales
    select count(*) into n_rows from public.app_feedback;
    select count(*) into n_audit from public.app_feedback where id = fb_sales;
    res := res || array['7', '[สั่ง 3] owner: อ่าน app_feedback เห็นแค่แถวของตัวเอง (แถวของ sales อ่านไม่ได้)',
      case
        when n_audit > 0 then 'FAIL (เห็นแถวของ sales)'
        when n_rows = 1 then 'PASS (1 แถว = ของตัวเอง)'
        else 'FAIL (' || n_rows || ' แถว)'
      end];

    -- 8: owner อ่านหมายเหตุได้ (เจ้าของต้องเห็นสิ่งที่ฝ่ายขายรายงาน)
    select count(*) into n_rows from public.receivable_notes where receivable_id = card_open;
    select count(*) into n_audit from public.receivable_latest_note where receivable_id = card_open;
    res := res || array['8', '[+] owner: อ่านหมายเหตุของการ์ดได้ทั้ง 2 รายการ และอ่าน view หมายเหตุล่าสุดได้',
      case when n_rows = 2 and n_audit = 1 then 'PASS'
           else format('FAIL (notes %s แถว, view %s แถว)', n_rows, n_audit) end];

    -- 9: ไม่มีแถว audit_logs ของ feedback
    select count(*) into n_audit from public.audit_logs where record_id in (fb_sales, fb_owner);
    res := res || array['9', '[+] feedback ไม่เขียน audit_logs (ข้อยกเว้นเดียวกับหมายเหตุ)',
      case when n_audit = 0 then 'PASS (0 แถว)' else 'FAIL (พบ ' || n_audit || ' แถว)' end];
    reset role;

    -- -----------------------------------------------------------------------
    -- 10–38: ลองเขียนทีละคำสั่ง แต่ละคำสั่งถูก rollback ทันที
    --   expect: ok      = ต้องสำเร็จ (>= 1 แถว)
    --           denied  = ต้องถูก RLS / สิทธิ์ปฏิเสธ (permission denied หรือ 0 แถว)
    --           <sqlstate>[:<name>] = ต้อง error ด้วยรหัสนี้ (และข้อความ หรือชื่อ constraint = name)
    --   who: none = role postgres ไม่มี JWT (เหมือนรันใน SQL Editor / service ที่ไม่มีผู้ใช้)
    -- -----------------------------------------------------------------------
    for w in
      select * from (values
        -- สั่ง 1: role ผิดเขียนไม่ได้
        (10, '[สั่ง 1] owner: เขียนหมายเหตุ → ปฏิเสธ (ฝ่ายขายเท่านั้น)', 'owner',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, 'owner เขียนไม่ได้'),
             'denied'),
        (11, '[สั่ง 1] ไม่มีผู้ใช้ล็อกอิน: เขียนหมายเหตุ → ปฏิเสธ', 'none',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, 'ไม่ล็อกอิน'),
             '42501:not_authenticated'),
        (12, '[สั่ง 1] ไม่มีผู้ใช้ล็อกอิน: ส่ง feedback → ปฏิเสธ', 'none',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week) values (''V1'', 5, 1)',
             '42501:not_authenticated'),
        -- สั่ง 2: แก้ / ลบไม่ได้ (ไม่มี policy UPDATE / DELETE ให้ใครเลย)
        (13, '[สั่ง 2] sales: แก้ข้อความหมายเหตุของตัวเอง → ปฏิเสธ', 'sales',
             format('update public.receivable_notes set body = %L where id = %L', 'แก้ทีหลัง', note1), 'denied'),
        (14, '[สั่ง 2] sales: ลบหมายเหตุ → ปฏิเสธ', 'sales',
             format('delete from public.receivable_notes where id = %L', note1), 'denied'),
        (15, '[สั่ง 2] sales: ย้ายหมายเหตุไปการ์ดอื่น → ปฏิเสธ (แก้แถวไม่ได้เลย)', 'sales',
             format('update public.receivable_notes set receivable_id = %L where id = %L', card_cancelled, note1), 'denied'),
        (16, '[สั่ง 2] owner: แก้หมายเหตุ → ปฏิเสธ', 'owner',
             format('update public.receivable_notes set body = %L where id = %L', 'owner แก้', note1), 'denied'),
        (17, '[สั่ง 2] owner: ลบหมายเหตุ → ปฏิเสธ', 'owner',
             format('delete from public.receivable_notes where id = %L', note1), 'denied'),
        (18, '[สั่ง 2] sales: แก้ feedback ของตัวเอง → ปฏิเสธ', 'sales',
             format('update public.app_feedback set helpful = 1 where id = %L', fb_sales), 'denied'),
        (19, '[สั่ง 2] sales: ลบ feedback ของตัวเอง → ปฏิเสธ', 'sales',
             format('delete from public.app_feedback where id = %L', fb_sales), 'denied'),
        (20, '[สั่ง 2] owner: ลบ feedback ของ sales → ปฏิเสธ', 'owner',
             format('delete from public.app_feedback where id = %L', fb_sales), 'denied'),
        -- สั่ง 4: การ์ดที่ยกเลิกเขียนหมายเหตุไม่ได้
        (21, '[สั่ง 4] sales: เขียนหมายเหตุในการ์ดที่ถูกยกเลิก → ปฏิเสธ', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_cancelled, 'การ์ดนี้ยกเลิกแล้ว'),
             '23514:note_receivable_cancelled'),
        -- กฎของข้อความหมายเหตุ
        (22, '[+] หมายเหตุว่าง → ปฏิเสธ', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, ''),
             '23514:receivable_notes_body_trimmed'),
        (23, '[+] หมายเหตุมีแต่ช่องว่าง → ปฏิเสธ', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, '   '),
             '23514:receivable_notes_body_trimmed'),
        (24, '[+] หมายเหตุมีช่องว่างหน้า → ปฏิเสธ (แอป trim ก่อนส่ง)', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, ' ขอเลื่อนจ่าย'),
             '23514:receivable_notes_body_trimmed'),
        (25, '[+] หมายเหตุยาว 1,001 ตัวอักษร → ปฏิเสธ', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, repeat('ก', 1001)),
             '23514:receivable_notes_body_len'),
        (26, '[+] หมายเหตุยาว 1,000 ตัวอักษรพอดี → ผ่าน', 'sales',
             format('insert into public.receivable_notes (receivable_id, body) values (%L, %L)', card_open, repeat('ก', 1000)),
             'ok'),
        -- กฎของ feedback: คำถามต้องตรงกับ role ของบัญชี
        (27, '[+] sales: ตอบคำถามของเจ้าของ (owner_asks_per_week) → ปฏิเสธ', 'sales',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week, sales_sheet_minutes) values (''V1'', 4, 2, 10)',
             '23514:app_feedback_owner_question'),
        (28, '[+] sales: ไม่ตอบคำถามของตัวเอง (sales_sheet_minutes ว่าง) → ปฏิเสธ', 'sales',
             'insert into public.app_feedback (app_version, helpful) values (''V1'', 4)',
             '23514:app_feedback_sales_question'),
        (29, '[+] owner: ตอบคำถามของฝ่ายขาย (sales_sheet_minutes) → ปฏิเสธ', 'owner',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week, sales_sheet_minutes) values (''V1'', 4, 2, 10)',
             '23514:app_feedback_sales_question'),
        (30, '[+] owner: ไม่ตอบคำถามของตัวเอง (owner_asks_per_week ว่าง) → ปฏิเสธ', 'owner',
             'insert into public.app_feedback (app_version, helpful) values (''V1'', 4)',
             '23514:app_feedback_owner_question'),
        (31, '[+] คะแนนข้อ 1 = 0 → ปฏิเสธ (1–5)', 'owner',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week) values (''V1'', 0, 1)',
             '23514:app_feedback_helpful_range'),
        (32, '[+] คะแนนข้อ 1 = 6 → ปฏิเสธ (1–5)', 'owner',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week) values (''V1'', 6, 1)',
             '23514:app_feedback_helpful_range'),
        (33, '[+] จำนวนครั้งติดลบ → ปฏิเสธ', 'owner',
             'insert into public.app_feedback (app_version, helpful, owner_asks_per_week) values (''V1'', 5, -1)',
             '23514:app_feedback_asks_range'),
        (34, '[+] เวลาทำตารางสรุป = 0 นาที (ไม่ต้องทำแล้ว) → ผ่าน', 'sales',
             'insert into public.app_feedback (app_version, helpful, sales_sheet_minutes) values (''V1'', 5, 0)',
             'ok'),
        (35, '[+] ข้อความ feedback ว่าง (ส่งสตริงว่างมาแทน null) → ปฏิเสธ', 'sales',
             'insert into public.app_feedback (app_version, helpful, issues, sales_sheet_minutes) values (''V1'', 5, '''', 0)',
             '23514:app_feedback_issues_trimmed'),
        (36, '[+] ข้าม feedback ข้อ 2 (issues = null) → ผ่าน', 'sales',
             'insert into public.app_feedback (app_version, helpful, sales_sheet_minutes) values (''V1'', 3, 5)',
             'ok'),
        (37, '[+] app_version ว่าง → ปฏิเสธ', 'sales',
             'insert into public.app_feedback (app_version, helpful, sales_sheet_minutes) values ('''', 3, 5)',
             '23514:app_feedback_version_trimmed'),
        (38, '[+] sales: ปั้นแถว audit_logs ของหมายเหตุเอง → ปฏิเสธ (audit_logs เขียนได้โดย trigger เท่านั้น)', 'sales',
             format('insert into public.audit_logs (user_id, action, table_name, record_id, new_value) values (%L, %L, %L, %L, %L)',
                    sales_id, 'create', 'receivables', note1, '{}'),
             'denied')
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
        raise exception 'v1_undo';  -- rollback สิ่งที่อาจถูกเปลี่ยน
      exception
        when raise_exception then
          if sqlerrm <> 'v1_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
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
    -- 39: ไม่ได้ล็อกอิน (anon) อ่านหมายเหตุ / feedback / view
    -- -----------------------------------------------------------------------
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    begin
      select count(*) into n_rows from public.receivable_notes;
      select count(*) into n_audit from public.app_feedback;
      outcome := case when n_rows = 0 and n_audit = 0 then 'PASS (0 แถว)'
                      else format('FAIL (notes %s, feedback %s)', n_rows, n_audit) end;
    exception when insufficient_privilege then outcome := 'PASS (permission denied)';
    end;
    reset role;
    res := res || array['39', '[+] anon: อ่าน receivable_notes และ app_feedback', outcome];

    -- -----------------------------------------------------------------------
    -- 40: sales ที่ is_active = false (rollback ตอนจบ)
    --     อ่านหมายเหตุได้ 0 แถว = view/ตารางใช้ RLS ของคนอ่านจริง และเขียนไม่ได้
    -- -----------------------------------------------------------------------
    update public.profiles set is_active = false where id = sales_id;
    perform set_config('request.jwt.claims', sales_claims, true);
    set local role authenticated;
    select count(*) into n_rows from public.receivable_notes;
    begin
      insert into public.receivable_notes (receivable_id, body) values (card_open, 'บัญชีถูกปิดแล้ว');
      outcome := 'FAIL (บันทึกได้)';
      raise exception 'v1_undo';
    exception
      when insufficient_privilege then outcome := 'PASS';
      when raise_exception then
        if sqlerrm <> 'v1_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
      when others then outcome := 'FAIL (' || sqlstate || ' ' || sqlerrm || ')';
    end;
    reset role;
    res := res || array['40', '[+] sales is_active = false: อ่านหมายเหตุได้ 0 แถว และเขียนหมายเหตุไม่ได้',
      case when n_rows = 0 then outcome else 'FAIL (อ่านได้ ' || n_rows || ' แถว)' end];

    raise exception 'v1_undo';
  exception when raise_exception then
    if sqlerrm <> 'v1_undo' then raise; end if;
  end;
  reset role;

  insert into v1_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

select n, test, result from v1_results order by n;

-- ---------------------------------------------------------------------------
-- 41–44: ตรวจโครงสร้าง (ไม่ต้องเขียนข้อมูล) — รันต่อจาก block ด้านบนได้เลย
--   41 RLS เปิดอยู่ทั้ง 2 ตาราง
--   42 ไม่มี policy UPDATE / DELETE / ALL ให้ใครเลย (append-only — [สั่ง 2] ระดับ policy)
--   43 สิทธิ์ระดับตาราง: authenticated ได้แค่ SELECT, INSERT · anon ไม่ได้อะไรเลย
--   44 Realtime: receivable_notes อยู่ใน publication, app_feedback ไม่ต้องอยู่
-- ---------------------------------------------------------------------------
select
  41                                                                  as n,
  'RLS เปิดอยู่: ' || x.tablename                                      as test,
  case when c.relrowsecurity then 'PASS' else 'FAIL (RLS ปิดอยู่)' end as result
from (values ('receivable_notes'), ('app_feedback')) as x(tablename)
join pg_class c on c.oid = ('public.' || x.tablename)::regclass
union all
select
  42,
  'ไม่มี policy UPDATE / DELETE: ' || x.tablename,
  coalesce(
    (select 'FAIL (' || string_agg(p.policyname || ' ' || p.cmd, ', ') || ')'
     from pg_policies p
     where p.schemaname = 'public' and p.tablename = x.tablename and p.cmd in ('UPDATE', 'DELETE', 'ALL')),
    'PASS (append-only)')
from (values ('receivable_notes'), ('app_feedback')) as x(tablename)
union all
select
  43,
  'สิทธิ์ระดับตาราง (authenticated / anon): ' || x.tablename,
  case
    when exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.tablename
        and g.grantee = 'anon'
    ) then 'FAIL (anon มีสิทธิ์)'
    when (
      select coalesce(string_agg(distinct g.privilege_type, ',' order by g.privilege_type), '')
      from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.tablename
        and g.grantee = 'authenticated'
    ) = 'INSERT,SELECT' then 'PASS (select, insert)'
    else 'FAIL (' || (
      select coalesce(string_agg(distinct g.privilege_type, ',' order by g.privilege_type), 'ไม่มีสิทธิ์')
      from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = x.tablename
        and g.grantee = 'authenticated'
    ) || ')'
  end
from (values ('receivable_notes'), ('app_feedback')) as x(tablename)
union all
select
  44,
  'Realtime: ' || x.tablename || (case when x.tablename = 'app_feedback' then ' (ไม่ต้องเปิด)' else '' end),
  case
    when x.tablename = 'app_feedback' then
      case when pt.tablename is null then 'PASS (ไม่อยู่ใน publication)' else 'FAIL (เปิดไว้โดยไม่จำเป็น)' end
    else
      case when pt.tablename is null then 'FAIL (ไม่อยู่ใน publication)' else 'PASS' end
  end
from (values ('receivable_notes'), ('app_feedback')) as x(tablename)
left join pg_publication_tables pt
  on pt.pubname = 'supabase_realtime' and pt.schemaname = 'public' and pt.tablename = x.tablename
order by n, test;
