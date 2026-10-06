-- 004_realtime.sql — M5
-- เปิด Realtime (postgres_changes) ให้ companies, receivables, payments, audit_logs
-- = เพิ่มตารางเข้า publication `supabase_realtime` ที่โปรเจกต์ Supabase สร้างไว้ให้แล้ว
--
-- แอปใช้ event เป็นแค่ "สัญญาณว่ามีของใหม่" แล้วโหลดจาก receivable_summary / payments / audit_logs ใหม่
-- ไม่คำนวณยอดเงินหรือสถานะจากตัว event (architecture.md ข้อ 7):
--   companies   → ชื่อบริษัทเปลี่ยน (company_name ใน view) หรือเพิ่ม/ปิดบริษัท
--   receivables → เพิ่ม / แก้ไข / ยกเลิกการ์ด
--   payments    → เพิ่ม / แก้ไข / ยกเลิกการจ่าย
--   audit_logs  → "ข้อมูล ณ" (= max(created_at)) และประวัติการแก้ไขในหน้ารายละเอียด
--
-- RLS ยังบังคับเหมือนเดิม: Realtime ตรวจ policy SELECT ของผู้ใช้เป็นรายแถวก่อนส่ง event
-- จึงส่งให้เฉพาะคนที่มีสิทธิ์อ่านแถวนั้น — ผู้ใช้ที่ไม่ล็อกอิน (anon) หรือ is_active = false
-- (my_role() เป็น null) ไม่ได้รับอะไรเลย ตารางทั้ง 4 เปิด RLS ไว้แล้วใน 002_core_tables.sql
--
-- ไม่ตั้ง `replica identity full`: ส่งแค่แถวใหม่ (ของเก่าส่งแค่ primary key) ซึ่งพอสำหรับการโหลดใหม่
-- และไม่ทำให้ค่าเดิมหลุดออกไปเกินจำเป็น
-- ไม่มี DELETE ในระบบนี้ (ใช้ is_cancelled / is_active) จึงไม่ต้องห่วงว่า event ของ DELETE
-- จะไม่ผ่าน RLS เหมือนที่ Supabase เตือนไว้
--
-- ต้องรัน 002_core_tables.sql ก่อน · รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว

do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'ไม่พบ publication supabase_realtime'
      using detail = 'เปิด Realtime ในโปรเจกต์ Supabase (Database → Replication) แล้วรันไฟล์นี้อีกครั้ง';
  end if;

  -- เพิ่มเฉพาะตารางที่ยังไม่อยู่ใน publication (รันซ้ำแล้วไม่ error)
  foreach v_table in array array['companies', 'receivables', 'payments', 'audit_logs']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
      raise notice 'เพิ่ม public.% เข้า publication supabase_realtime', v_table;
    else
      raise notice 'public.% อยู่ใน publication supabase_realtime อยู่แล้ว', v_table;
    end if;
  end loop;
end $$;

-- ตรวจผล: ต้องได้ PASS ทั้ง 2 ช่องของทั้ง 4 ตาราง (ชุดตรวจเต็มอยู่ใน supabase/tests/m5_checks.sql)
select
  x.tablename                                                            as "ตาราง",
  case when pt.tablename is null then 'FAIL (ไม่อยู่ใน publication)' else 'PASS' end as "realtime",
  case when c.relrowsecurity then 'PASS' else 'FAIL (RLS ปิดอยู่)' end             as "rls"
from (values ('companies'), ('receivables'), ('payments'), ('audit_logs')) as x(tablename)
join pg_class c on c.oid = ('public.' || x.tablename)::regclass
left join pg_publication_tables pt
  on pt.pubname = 'supabase_realtime'
 and pt.schemaname = 'public'
 and pt.tablename = x.tablename
order by x.tablename;
