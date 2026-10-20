-- 007_owner_notes.sql — V2 ข้อ 2
-- **เจ้าของเขียนหมายเหตุบนการ์ดได้** (เดิม 005 ให้เขียนได้แค่ฝ่ายขาย)
-- ที่มา: feedback จากอาจารย์ 20 ต.ค. 2569 — "เจ้าของต้องติดต่อฝ่ายขายได้ ไม่ใช่ดูอย่างเดียว"
-- (prd.md ข้อ 5 รายการที่ 11 และตารางสิทธิ์ข้อ 9 · schema.md ข้อ 3.6 / 4.1 / 5)
--
-- เปลี่ยนแค่ 2 อย่าง:
--   1. policy INSERT ของ receivable_notes: sales เท่านั้น → ผู้ใช้ที่ล็อกอินและ is_active ทุกคน
--   2. view receivable_latest_note: ต่อท้ายคอลัมน์ created_by_role เพื่อให้การ์ดในหน้าตาราง
--      ติดป้ายได้ว่าหมายเหตุล่าสุดเป็นของ "เจ้าของ" หรือ "ฝ่ายขาย" และทำสีให้เด่นเมื่อเป็นของเจ้าของ
--      (หน้าตารางไม่ได้อ่าน profiles จึงต้องได้ role มาจาก view นี้ ไม่ใช่ขอเพิ่มอีก 1 คำขอ)
--
-- สิ่งที่ **ไม่** เปลี่ยน (ยืนยันด้วย supabase/tests/owner_notes_checks.sql):
--   - receivable_notes ยังเป็นตารางต่อท้ายอย่างเดียว: ไม่มี policy UPDATE / DELETE ให้ใครเลย
--     ไม่มี is_cancelled และยังไม่มี trigger เขียน audit_logs (เหตุผลเต็มใน schema.md 3.6)
--     เขียนผิด → เขียนรายการใหม่ ทั้ง 2 รายการยังอยู่
--   - กฎ "การ์ดที่ยกเลิกแล้วเขียนหมายเหตุไม่ได้" (note_receivable_cancelled) ยังบังคับเหมือนเดิม
--   - **เจ้าของยังเขียนตารางเงินทุกตารางไม่ได้** (companies / receivables / payments)
--     ไฟล์นี้ไม่แตะ policy ของ 3 ตารางนั้นเลย และ select ท้ายไฟล์ตรวจซ้ำให้
--   - created_by ของหมายเหตุยังมาจาก trigger set_note_meta() (auth.uid()) ไม่ใช่จากแอป
--   - สิทธิ์ระดับตารางเดิม (grant select, insert) ครอบคลุม owner อยู่แล้ว จึงไม่ต้อง grant เพิ่ม
--
-- ต้องรัน 001–006 ก่อน · รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว
-- (ต้องการเปลี่ยน → เขียน 008_*.sql) · ชุดตรวจ PASS/FAIL: supabase/tests/owner_notes_checks.sql
-- รันไฟล์นี้ได้ทันทีโดยแอปที่ deploy อยู่ไม่พัง: ของเดิมถูกขยายสิทธิ์ ไม่มีอะไรถูกบังคับเพิ่ม
-- และคอลัมน์ใหม่ของ view ต่อท้ายเท่านั้น (AGENTS.md — ขั้น expand)

-- ---------------------------------------------------------------------------
-- 1. policy INSERT: ผู้ใช้ที่ล็อกอินและ is_active ทุกคน (เจ้าของ + ฝ่ายขาย)
--    my_role() เป็น null = ไม่มี profile หรือ is_active = false → เขียนไม่ได้
--    ชื่อ policy เปลี่ยนตามความหมายใหม่ จึง drop ตัวเดิมแล้วสร้างใหม่
--    (ไม่มีช่วงที่ "ไม่มี policy insert" ให้ใช้งานจริง เพราะทั้งไฟล์รันใน transaction เดียว)
-- ---------------------------------------------------------------------------
drop policy "receivable_notes_insert_sales" on public.receivable_notes;

create policy "receivable_notes_insert_active_users"
  on public.receivable_notes for insert to authenticated
  with check ((select public.my_role()) is not null);

-- ---------------------------------------------------------------------------
-- 2. view receivable_latest_note (schema.md ข้อ 4.1) — ต่อท้าย created_by_role
--    create or replace view: คอลัมน์เดิมชื่อ / ชนิด / ลำดับเหมือน 005 เพิ่มได้แค่ท้ายสุด
--    role อ่านจาก profiles ตอนอ่าน ไม่เก็บซ้ำในตาราง receivable_notes:
--      - ตารางนี้เป็นแบบต่อท้ายอย่างเดียว เพิ่มคอลัมน์แล้วแถวเก่าจะเป็น null และ backfill ไม่ได้
--        โดยไม่ขัดกับกฎของตัวเอง (ไม่มี policy UPDATE)
--      - role ของผู้ใช้ในระบบนี้ไม่เปลี่ยน (แก้ได้จาก SQL Editor เท่านั้น — schema.md 3.1)
--    profiles: ผู้ใช้ที่ล็อกอินและ is_active อ่านได้ทุกแถว (001) → join ไม่ทำให้แถวหาย
--    และ anon / บัญชีที่ถูกปิด อ่าน receivable_notes ไม่ได้อยู่แล้ว
-- ---------------------------------------------------------------------------
create or replace view public.receivable_latest_note
with (security_invoker = true)
as
select distinct on (n.receivable_id)
  n.receivable_id,
  n.id         as note_id,
  n.body,
  n.created_by,
  n.created_at,
  -- ใหม่ใน 007 (ต่อท้าย): เจ้าของ ('owner') หรือ ฝ่ายขาย ('sales')
  p.role       as created_by_role
from public.receivable_notes n
join public.profiles p on p.id = n.created_by
order by n.receivable_id, n.created_at desc, n.id desc;

comment on view public.receivable_latest_note is
  'หมายเหตุล่าสุด 1 แถวต่อ 1 การ์ด สำหรับการ์ดในหน้าตาราง (schema.md 4.1) การ์ดที่ยังไม่มีหมายเหตุไม่มีแถวที่นี่ · 007: created_by_role บอกว่าเจ้าของหรือฝ่ายขายเขียน';

-- สิทธิ์เหมือน 005 (create or replace คงสิทธิ์เดิมไว้อยู่แล้ว เขียนซ้ำให้ชัด)
revoke all on table public.receivable_latest_note from anon, authenticated;
grant select on table public.receivable_latest_note to authenticated;

-- ---------------------------------------------------------------------------
-- 3. ตรวจผลเบื้องต้น: ต้องได้ PASS ทุกแถว (ชุดตรวจเต็มอยู่ใน supabase/tests/owner_notes_checks.sql)
-- ---------------------------------------------------------------------------
select
  'เจ้าของ + ฝ่ายขาย เขียนหมายเหตุได้'                                        as "ข้อ",
  case when (
         select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'receivable_notes' and cmd = 'INSERT'
           -- pg แสดงเงื่อนไขเป็น (( SELECT my_role() AS my_role) IS NOT NULL) จึงเทียบ 2 ชิ้นแยกกัน
           and with_check like '%my_role%' and with_check like '%IS NOT NULL%'
       ) = 1 then 'PASS' else 'FAIL (policy insert ไม่ตรง)' end                as "ผล"
union all
select
  'หมายเหตุยังแก้ / ลบไม่ได้ (ไม่มี policy UPDATE / DELETE)',
  case when exists (
         select 1 from pg_policies
         where schemaname = 'public' and tablename = 'receivable_notes'
           and cmd in ('UPDATE', 'DELETE', 'ALL')
       ) then 'FAIL (มี policy แก้/ลบ)' else 'PASS' end
union all
select
  'สิทธิ์ระดับตารางของ receivable_notes = select, insert เท่านั้น',
  case when (
         select coalesce(string_agg(distinct privilege_type, ',' order by privilege_type), '')
         from information_schema.role_table_grants
         where table_schema = 'public' and table_name = 'receivable_notes' and grantee = 'authenticated'
       ) = 'INSERT,SELECT' then 'PASS' else 'FAIL' end
union all
select
  'หมายเหตุยังไม่มี trigger เขียน audit_logs (ตามเจตนา — schema.md 3.6)',
  case when (
         select count(*) from pg_trigger
         where tgrelid = 'public.receivable_notes'::regclass and not tgisinternal
       ) = 2 then 'PASS (มีแค่ trg_10_set_meta และ trg_20_check_rules)'
       else 'FAIL (จำนวน trigger เปลี่ยน)' end
union all
select
  'เจ้าของยังเขียนตารางเงินไม่ได้ (companies / receivables / payments)',
  case when exists (
         select 1 from pg_policies
         where schemaname = 'public'
           and tablename in ('companies', 'receivables', 'payments')
           and cmd in ('INSERT', 'UPDATE', 'ALL')
           and coalesce(with_check, qual, '') not like '%sales%'
       ) then 'FAIL (มี policy เขียนที่ไม่ได้จำกัดเป็น sales)' else 'PASS' end
union all
select
  'receivable_latest_note มีคอลัมน์ created_by_role ต่อท้าย',
  case when (
         select string_agg(column_name, ',' order by ordinal_position)
         from information_schema.columns
         where table_schema = 'public' and table_name = 'receivable_latest_note'
       ) = 'receivable_id,note_id,body,created_by,created_at,created_by_role'
       then 'PASS' else 'FAIL (คอลัมน์ไม่ตรง)' end;
