-- m1_checks.sql — ตรวจ RLS ของ M1 แบบ PASS/FAIL
-- วิธีใช้: แก้อีเมล 2 บรรทัดด้านล่าง แล้วรันทั้งไฟล์ใน Supabase SQL Editor
-- ไม่เปลี่ยนข้อมูลจริง: ทุกการเขียนที่ทดลองถูก rollback เสมอ

create temp table if not exists m1_results (n int, test text, result text);
truncate m1_results;

do $$
declare
  owner_email constant text := 'OWNER_EMAIL@example.com';
  sales_email constant text := 'SALES_EMAIL@example.com';
  owner_id uuid := (select id from auth.users where email = owner_email);
  sales_id uuid := (select id from auth.users where email = sales_email);
  stranger_id uuid := gen_random_uuid();  -- ล็อกอินได้แต่ไม่มีแถวใน profiles
  res text[] := '{}';
  w record;
  outcome text;
  n_rows int;
  v_role public.user_role;
begin
  if owner_id is null or sales_id is null then
    raise exception 'ไม่พบอีเมลใน auth.users — แก้ owner_email / sales_email ก่อนรัน';
  end if;

  -- 1–3: อ่าน
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_role := public.my_role();
  res := res || array['1', 'owner: my_role() = owner', case when v_role = 'owner' then 'PASS' else 'FAIL (' || coalesce(v_role::text, 'null') || ')' end];
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', sales_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_role := public.my_role();
  res := res || array['2', 'sales: my_role() = sales', case when v_role = 'sales' then 'PASS' else 'FAIL (' || coalesce(v_role::text, 'null') || ')' end];
  select count(*) into n_rows from public.profiles;
  res := res || array['3', 'sales: อ่าน profiles ได้ทุกแถว (>= 2)', case when n_rows >= 2 then 'PASS' else 'FAIL (' || n_rows || ')' end];
  reset role;

  -- 4–9: การเขียนที่ต้องถูกปฏิเสธ
  for w in
    select * from (values
      (4, 'sales: แก้ role ตัวเองเป็น owner',  sales_id, format('update public.profiles set role = %L where id = %L', 'owner', sales_id)),
      (5, 'owner: แก้ role ตัวเอง',             owner_id, format('update public.profiles set role = %L where id = %L', 'sales', owner_id)),
      (6, 'sales: แก้ display_name ของ owner',  sales_id, format('update public.profiles set display_name = %L where id = %L', 'x', owner_id)),
      (7, 'sales: เปิด is_active ตัวเอง',        sales_id, format('update public.profiles set is_active = true where id = %L', sales_id)),
      (8, 'sales: insert profile ใหม่',          sales_id, format('insert into public.profiles (id, display_name, role) values (%L, %L, %L)', stranger_id, 'x', 'owner')),
      (9, 'owner: ลบ profile',                  owner_id, format('delete from public.profiles where id = %L', sales_id))
    ) v(n, label, as_user, stmt)
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', w.as_user, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      execute w.stmt;
      get diagnostics n_rows = row_count;
      outcome := case when n_rows = 0 then 'PASS (0 แถว)' else 'FAIL (' || n_rows || ' แถวถูกเปลี่ยน)' end;
      raise exception 'm1_undo';  -- rollback สิ่งที่อาจถูกเปลี่ยน
    exception
      when insufficient_privilege then outcome := 'PASS (permission denied)';
      when raise_exception then
        if sqlerrm <> 'm1_undo' then outcome := 'FAIL (' || sqlerrm || ')'; end if;
      when foreign_key_violation then outcome := 'FAIL (ผ่าน RLS แต่ติด FK)';
    end;
    reset role;
    res := res || array[w.n::text, w.label, outcome];
  end loop;

  -- 10–11: ไม่ได้ล็อกอิน (anon)
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  begin
    select count(*) into n_rows from public.profiles;
    outcome := case when n_rows = 0 then 'PASS (0 แถว)' else 'FAIL (' || n_rows || ' แถว)' end;
  exception when insufficient_privilege then outcome := 'PASS (permission denied)';
  end;
  res := res || array['10', 'anon: อ่าน profiles', outcome];
  begin
    perform public.my_role();
    outcome := 'FAIL (เรียกได้)';
  exception when insufficient_privilege then outcome := 'PASS (permission denied)';
  end;
  res := res || array['11', 'anon: เรียก my_role()', outcome];
  reset role;

  -- 12: ล็อกอินได้แต่ไม่มีแถวใน profiles
  perform set_config('request.jwt.claims', json_build_object('sub', stranger_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_role := public.my_role();
  select count(*) into n_rows from public.profiles;
  res := res || array['12', 'ไม่มี profile: my_role() = null และอ่านได้ 0 แถว',
                      case when v_role is null and n_rows = 0 then 'PASS' else 'FAIL' end];
  reset role;

  -- 13: sales ที่ is_active = false (ปิดชั่วคราวแล้ว rollback)
  begin
    update public.profiles set is_active = false where id = sales_id;
    perform set_config('request.jwt.claims', json_build_object('sub', sales_id, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_role := public.my_role();
    select count(*) into n_rows from public.profiles;
    reset role;
    res := res || array['13', 'sales is_active = false: my_role() = null และอ่านได้ 0 แถว',
                        case when v_role is null and n_rows = 0 then 'PASS' else 'FAIL' end];
    raise exception 'm1_undo';
  exception when raise_exception then
    if sqlerrm <> 'm1_undo' then raise; end if;
  end;
  reset role;

  insert into m1_results
  select res[i]::int, res[i + 1], res[i + 2]
  from generate_series(1, array_length(res, 1), 3) as i;
end $$;

select n, test, result from m1_results order by n;
