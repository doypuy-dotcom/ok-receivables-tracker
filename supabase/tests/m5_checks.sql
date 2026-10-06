-- m5_checks.sql — ตรวจการเปิด Realtime (004_realtime.sql) แบบ PASS/FAIL
-- วิธีใช้: รันทั้งไฟล์ใน Supabase SQL Editor (หลังรัน 004) — อ่านอย่างเดียว ไม่แก้ข้อมูล
-- ตรวจเรื่องที่ทำให้ Realtime ปลอดภัยและใช้งานได้ ไม่ได้ตรวจตัว websocket (ข้อนั้นทดสอบด้วย 2 บัญชีจริง)

with want(tablename) as (
  values ('companies'), ('receivables'), ('payments'), ('audit_logs')
),
info as (
  select
    w.tablename,
    c.relrowsecurity                   as rls_on,
    c.relreplident                     as replident,
    pt.tablename is not null           as in_pub,
    has_table_privilege('anon', 'public.' || w.tablename, 'select') as anon_select
  from want w
  join pg_class c on c.oid = ('public.' || w.tablename)::regclass
  left join pg_publication_tables pt
    on pt.pubname = 'supabase_realtime'
   and pt.schemaname = 'public'
   and pt.tablename = w.tablename
),
pub as (
  select pubinsert, pubupdate, pubdelete from pg_publication where pubname = 'supabase_realtime'
),
checks(n, test, result) as (
  select 1, 'ทั้ง 4 ตารางอยู่ใน publication supabase_realtime',
    case when count(*) filter (where not in_pub) = 0 then 'PASS'
         else 'FAIL (ยังไม่อยู่: ' || string_agg(tablename, ', ') filter (where not in_pub) || ')' end
  from info

  union all
  select 2, 'RLS เปิดอยู่ทั้ง 4 ตาราง (Realtime จึงกรองแถวตามสิทธิ์ผู้ใช้)',
    case when count(*) filter (where not rls_on) = 0 then 'PASS'
         else 'FAIL (RLS ปิด: ' || string_agg(tablename, ', ') filter (where not rls_on) || ')' end
  from info

  union all
  select 3, 'anon (ไม่ล็อกอิน) ไม่มีสิทธิ์ select ทั้ง 4 ตาราง → ไม่ได้รับ event',
    case when count(*) filter (where anon_select) = 0 then 'PASS'
         else 'FAIL (anon อ่านได้: ' || string_agg(tablename, ', ') filter (where anon_select) || ')' end
  from info

  union all
  select 4, 'publication ส่ง event ของ insert และ update',
    case when not exists (select 1 from pub) then 'FAIL (ไม่พบ publication supabase_realtime)'
         when (select pubinsert and pubupdate from pub) then 'PASS'
         else 'FAIL (insert=' || (select pubinsert::text from pub) || ' update=' || (select pubupdate::text from pub) || ')' end

  union all
  -- 'f' = full (ส่งแถวเก่าทั้งแถวออกไปด้วย) — ไม่ต้องใช้ เพราะแอปโหลดใหม่ ไม่อ่านค่าจาก event
  select 5, 'replica identity ไม่ใช่ full (ไม่ส่งค่าเดิมทั้งแถวออกไป)',
    case when count(*) filter (where replident = 'f') = 0 then 'PASS'
         else 'FAIL (full: ' || string_agg(tablename, ', ') filter (where replident = 'f') || ')' end
  from info

  union all
  -- event ของ DELETE ไม่ผ่าน RLS (Supabase เตือนไว้) ระบบนี้ไม่มี DELETE จึงต้องไม่มี policy DELETE
  select 6, 'ไม่มี policy DELETE บนตารางไหนเลย',
    case when count(*) = 0 then 'PASS'
         else 'FAIL (' || string_agg(tablename || '.' || policyname, ', ') || ')' end
  from pg_policies
  where schemaname = 'public' and cmd = 'DELETE'
)
select n, test, result from checks order by n;
