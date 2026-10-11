-- 005_notes_and_feedback.sql — V1 รอบ ข
-- ตาราง receivable_notes (schema.md 3.6) + app_feedback (schema.md 3.7),
-- RLS + policy (schema.md 5), trigger ใส่คนเขียน/เวลาและกฎการ์ดที่ยกเลิก,
-- view receivable_latest_note (schema.md 4.1), เปิด Realtime ให้ receivable_notes
-- ต้องรัน 001–004 ก่อน (ใช้ public.my_role(), public.profiles, public.receivables)
-- รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว (ต้องการเปลี่ยน → เขียน 006_*.sql)
--
-- **2 ตารางนี้เป็นแบบต่อท้ายอย่างเดียว (append-only)**: ไม่มี policy UPDATE และ DELETE ให้ใครเลย
-- จึงไม่มี updated_at / updated_by, ไม่มี is_cancelled และ **ไม่มี trigger เขียน audit_logs**
-- เพราะแถวที่เขียนแล้วเปลี่ยนไม่ได้อีก ตัวตารางเองจึงเป็นประวัติในตัวแล้ว
-- (ข้อยกเว้นเดียวของกฎ "ทุกการเขียนลง audit_logs" — เหตุผลเต็มใน schema.md 3.6 และ AGENTS.md)
-- เขียนหมายเหตุผิด → เขียนรายการใหม่ ทั้ง 2 รายการยังอยู่
--
-- ข้อความ error ของกฎธุรกิจ (ให้แอปแปลเป็นภาษาคน — schema.md 6):
--   42501 not_authenticated              เขียนโดยไม่มีผู้ใช้ล็อกอิน หรือบัญชีถูกปิด (is_active = false)
--   23514 note_receivable_cancelled      เขียนหมายเหตุในการ์ดที่ถูกยกเลิก
--   23514 receivable_notes_body_trimmed / receivable_notes_body_len   ข้อความว่าง / มีช่องว่างหน้า-หลัง / ยาวเกิน 1,000
--   23514 app_feedback_*                 ค่าผิดกฎในตาราง feedback (ชื่อ constraint)

-- ---------------------------------------------------------------------------
-- 1. receivable_notes — หมายเหตุบนการ์ด (schema.md 3.6)
--    ผูกกับ receivables ไม่ใช่ companies: เรื่องที่จดเป็นเรื่องของยอดค้างใบนั้น
--    (ขอเลื่อนจ่ายรอบนี้ / โอนมาขาดเพราะค่าธรรมเนียม) ไม่ใช่นิสัยประจำของบริษัท
--    ไม่มี on delete cascade: ห้ามลบการ์ด (ใช้ is_cancelled)
-- ---------------------------------------------------------------------------
create table public.receivable_notes (
  id            uuid primary key default gen_random_uuid(),
  receivable_id uuid not null references public.receivables (id),
  body          text not null,
  created_at    timestamptz not null default now(),
  created_by    uuid not null references public.profiles (id),
  -- ห้ามว่าง ห้ามมีแต่ช่องว่าง ห้ามมีช่องว่างหน้า/หลัง (แอป trim ก่อนส่ง)
  constraint receivable_notes_body_trimmed check (body = btrim(body) and body <> ''),
  -- จำกัดความยาวเพื่อให้การ์ดในหน้าตารางและหน้ารายละเอียดยังอ่านได้ (และกันการวางข้อความยาวผิดที่)
  constraint receivable_notes_body_len     check (length(body) <= 1000)
);

comment on table public.receivable_notes is
  'หมายเหตุบนการ์ด: ต่อท้ายอย่างเดียว แก้/ลบ/ยกเลิกไม่ได้ จึงเป็นประวัติในตัว (ไม่มี audit_logs — schema.md 3.6)';

-- หน้ารายละเอียดและ view หมายเหตุล่าสุดอ่านตามการ์ด เรียงตามเวลา
create index receivable_notes_receivable_id_idx on public.receivable_notes (receivable_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. app_feedback — ความคิดเห็นเกี่ยวกับแอป (schema.md 3.7, prd.md 11)
--    user_id / role / created_at ใส่โดย trigger (ค่าที่แอปส่งมาถูกเขียนทับ)
--    app_version มาจากแอป เพราะ database ไม่รู้ว่าเครื่องนั้นโหลดโค้ดเวอร์ชันไหนไว้
-- ---------------------------------------------------------------------------
create table public.app_feedback (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles (id),
  role                public.user_role not null,
  app_version         text not null,
  -- ข้อ 1 (ทุกคน): แอปช่วยงานได้แค่ไหน 1 = ไม่ช่วยเลย … 5 = ช่วยมาก
  helpful             smallint not null,
  -- ข้อ 2 (ทุกคน, ข้ามได้): อะไรติดขัด / อยากให้เพิ่ม
  issues              text,
  -- ข้อ 3 (เจ้าของ): สัปดาห์นี้ต้องถามฝ่ายขายหรือเช็คบัญชีเองกี่ครั้ง (baseline 3 ครั้ง/สัปดาห์)
  owner_asks_per_week integer,
  -- ข้อ 4 (ฝ่ายขาย): **เดือนนี้** ทำตารางสรุปแบบเดิมให้เจ้าของไปกี่นาที — 0 = ไม่ต้องทำแล้ว
  --   หน่วยเป็น นาที/เดือน ตรงกับ baseline 30 นาที/เดือน (ทำเดือนละครั้งตอนสิ้นเดือน)
  --   ถามเป็นรายเดือนไม่ใช่รายสัปดาห์ เพราะงานนี้ทำเดือนละครั้ง ถ้าถามรายสัปดาห์จะได้ 0
  --   เกือบทุกสัปดาห์แม้ยังไม่มีแอป จึงวัดอะไรไม่ได้ (prd.md ข้อ 11 และ 12)
  sales_sheet_minutes integer,
  created_at          timestamptz not null default now(),
  constraint app_feedback_version_trimmed  check (app_version = btrim(app_version) and app_version <> ''),
  constraint app_feedback_version_len      check (length(app_version) <= 20),
  constraint app_feedback_helpful_range    check (helpful between 1 and 5),
  constraint app_feedback_issues_trimmed   check (issues is null or (issues = btrim(issues) and issues <> '')),
  constraint app_feedback_issues_len       check (issues is null or length(issues) <= 2000),
  -- คำถามของแต่ละ role: ตอบคำถามของ role อื่นไม่ได้ และข้ามคำถามของ role ตัวเองไม่ได้
  constraint app_feedback_owner_question   check ((role = 'owner') = (owner_asks_per_week is not null)),
  constraint app_feedback_sales_question   check ((role = 'sales') = (sales_sheet_minutes is not null)),
  -- ช่วงที่เป็นไปได้ (กันพิมพ์ผิดจนค่าเฉลี่ยในรายงานเพี้ยน)
  constraint app_feedback_asks_range       check (owner_asks_per_week is null or owner_asks_per_week between 0 and 200),
  -- 10000 นาที ≈ 7 วันทำงานเต็ม: สูงเกินกว่างานสรุปเดือนละครั้งจะเป็นไปได้ จึงใช้เป็นเพดานกันพิมพ์ผิด
  constraint app_feedback_minutes_range    check (sales_sheet_minutes is null or sales_sheet_minutes between 0 and 10000)
);

comment on table public.app_feedback is
  'feedback ของผู้ใช้แยกตามเวอร์ชัน (prd.md 11): ส่งได้ อ่านได้แค่ของตัวเอง แก้/ลบไม่ได้ ผู้พัฒนาอ่านทั้งหมดจาก SQL Editor';

-- รายงานสรุปอ่านแยกตาม app_version × role (supabase/queries/feedback_report.sql)
create index app_feedback_version_role_idx on public.app_feedback (app_version, role, created_at);

-- ---------------------------------------------------------------------------
-- 3. trigger functions
--    search_path = '' : ทุกชื่อต้องระบุ schema เต็ม (เหมือน 001/002)
--    ลำดับ trigger ในตารางเดียวกันเรียงตามชื่อ: trg_10_* → trg_20_*
-- ---------------------------------------------------------------------------

-- 3.1 receivable_notes: ใส่คนเขียน + เวลาอัตโนมัติ และปฏิเสธการเขียนที่ไม่มีผู้ใช้ล็อกอิน
--     ไม่ใช่ security definer: ไม่ได้อ่านหรือเขียนตารางอื่น
--     ไม่มีสาขา UPDATE: ตารางนี้ไม่มี policy UPDATE ให้ใคร trigger จึงผูกกับ insert เท่านั้น
create function public.set_note_meta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated'
      using errcode = 'insufficient_privilege',
            detail  = 'ต้องล็อกอินก่อนเขียนหมายเหตุ (หมายเหตุต้องรู้ว่าใครเขียน)';
  end if;

  new.created_at := now();
  new.created_by := v_user;
  return new;
end
$$;

-- 3.2 receivable_notes: เขียนหมายเหตุในการ์ดที่ถูกยกเลิกไม่ได้ (กฎเดียวกับการเพิ่มการจ่าย — schema.md 3.4)
--     หมายเหตุเดิมของการ์ดนั้นยังอ่านได้ตามปกติ และยกเลิกการ์ดไม่ลบหมายเหตุ
--     security definer: อ่านสถานะการ์ดจากแถวจริง ไม่ขึ้นกับ RLS ของคนที่เรียก
--     ชื่อ error ตั้งเป็น note_receivable_cancelled ไม่ใช่ receivable_cancelled
--     เพื่อให้แอปแยกข้อความได้ ("เขียนหมายเหตุไม่ได้" ไม่ใช่ "เพิ่มการจ่ายไม่ได้")
create function public.check_note_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cancelled boolean;
begin
  select r.is_cancelled into v_cancelled
  from public.receivables r
  where r.id = new.receivable_id;

  if not found then
    return new;  -- ไม่มีการ์ดนี้ → foreign key ปฏิเสธเอง
  end if;

  if v_cancelled then
    raise exception 'note_receivable_cancelled'
      using errcode = 'check_violation',
            detail  = 'การ์ดนี้ถูกยกเลิกแล้ว เขียนหมายเหตุไม่ได้';
  end if;

  return new;
end
$$;

-- 3.3 app_feedback: ใส่ผู้ส่ง + role + เวลาอัตโนมัติ (ค่าที่แอปส่งมาถูกเขียนทับทุกครั้ง)
--     role มาจาก my_role() ไม่ใช่จากแอป จึงอ้าง role อื่นเพื่อข้าม constraint ของคำถามไม่ได้
--     my_role() เป็น null = ไม่มี profile หรือ is_active = false → เขียนไม่ได้
create function public.set_feedback_meta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role public.user_role := public.my_role();
begin
  if v_user is null or v_role is null then
    raise exception 'not_authenticated'
      using errcode = 'insufficient_privilege',
            detail  = 'ต้องล็อกอินด้วยบัญชีที่ใช้งานอยู่ก่อนส่งความคิดเห็น';
  end if;

  new.user_id    := v_user;
  new.role       := v_role;
  new.created_at := now();
  return new;
end
$$;

-- trigger functions ถูกเรียกโดย trigger เท่านั้น ไม่ต้องให้ใครเรียกตรง
revoke execute on function public.set_note_meta()     from public, anon, authenticated;
revoke execute on function public.check_note_rules()  from public, anon, authenticated;
revoke execute on function public.set_feedback_meta() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. triggers (insert เท่านั้น — ไม่มี update / delete ให้ใคร)
-- ---------------------------------------------------------------------------
create trigger trg_10_set_meta
  before insert on public.receivable_notes
  for each row execute function public.set_note_meta();
create trigger trg_20_check_rules
  before insert on public.receivable_notes
  for each row execute function public.check_note_rules();

create trigger trg_10_set_meta
  before insert on public.app_feedback
  for each row execute function public.set_feedback_meta();

-- ---------------------------------------------------------------------------
-- 5. RLS (schema.md 5)
--    receivable_notes: อ่าน = ผู้ใช้ที่ล็อกอินและ is_active ทุกคน (เจ้าของอ่านได้), เพิ่ม = sales เท่านั้น
--    app_feedback:     อ่านและเพิ่ม = แถวของตัวเองเท่านั้น (เจ้าของไม่เห็นคำตอบของฝ่ายขายและกลับกัน)
--    ทั้ง 2 ตาราง: ไม่มี policy UPDATE และ DELETE ให้ใครเลย (append-only)
-- ---------------------------------------------------------------------------
alter table public.receivable_notes enable row level security;
alter table public.app_feedback     enable row level security;

create policy "receivable_notes_select_active_users"
  on public.receivable_notes for select to authenticated
  using ((select public.my_role()) is not null);
create policy "receivable_notes_insert_sales"
  on public.receivable_notes for insert to authenticated
  with check ((select public.my_role()) = 'sales');

-- user_id ถูก trigger ตั้งเป็น auth.uid() อยู่แล้ว (RLS with check ตรวจแถวหลัง before trigger)
-- เขียนเงื่อนไขนี้ซ้ำอีกชั้นเพื่อให้ policy อ่านรู้เรื่องด้วยตัวเอง ไม่ต้องไปอ่าน trigger ประกอบ
create policy "app_feedback_select_own"
  on public.app_feedback for select to authenticated
  using (user_id = (select auth.uid()) and (select public.my_role()) is not null);
create policy "app_feedback_insert_own"
  on public.app_feedback for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.my_role()) is not null);

-- สิทธิ์ระดับตารางอีกชั้น: ไม่มี update / delete ให้ใคร, anon ไม่ได้อะไรเลย
revoke all on table public.receivable_notes, public.app_feedback from anon, authenticated;
grant select, insert on table public.receivable_notes, public.app_feedback to authenticated;

-- ---------------------------------------------------------------------------
-- 6. view receivable_latest_note (schema.md 4.1) — หมายเหตุล่าสุด 1 แถวต่อ 1 การ์ด
--    ใช้บนการ์ดในหน้าตาราง: เจ้าของเห็นหมายเหตุล่าสุดโดยไม่ต้องกดเข้าหน้ารายละเอียด
--    security_invoker = true: ใช้ RLS ของคนที่อ่าน (เหมือน receivable_summary)
--    ตัดด้วย id ต่อจาก created_at เพื่อให้ผลคงที่เมื่อ 2 หมายเหตุมีเวลาเท่ากันเป๊ะ
-- ---------------------------------------------------------------------------
create view public.receivable_latest_note
with (security_invoker = true)
as
select distinct on (n.receivable_id)
  n.receivable_id,
  n.id         as note_id,
  n.body,
  n.created_by,
  n.created_at
from public.receivable_notes n
order by n.receivable_id, n.created_at desc, n.id desc;

comment on view public.receivable_latest_note is
  'หมายเหตุล่าสุด 1 แถวต่อ 1 การ์ด สำหรับการ์ดในหน้าตาราง (schema.md 4.1) การ์ดที่ยังไม่มีหมายเหตุไม่มีแถวที่นี่';

revoke all on table public.receivable_latest_note from anon, authenticated;
grant select on table public.receivable_latest_note to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Realtime — เพิ่ม receivable_notes เข้า publication supabase_realtime
--    ฝ่ายขายเขียนหมายเหตุบนคอม → หน้าจอเจ้าของบนมือถืออัปเดตเอง (architecture.md 7)
--    app_feedback ไม่ต้องเปิด: ไม่มีหน้าจอไหนต้องอัปเดตตาม และอ่านได้แค่ของตัวเอง
--    วิธีเดียวกับ 004_realtime.sql (รันซ้ำแล้วไม่ error)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'ไม่พบ publication supabase_realtime'
      using detail = 'เปิด Realtime ในโปรเจกต์ Supabase (Database → Replication) แล้วรันไฟล์นี้อีกครั้ง';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'receivable_notes'
  ) then
    execute 'alter publication supabase_realtime add table public.receivable_notes';
    raise notice 'เพิ่ม public.receivable_notes เข้า publication supabase_realtime';
  else
    raise notice 'public.receivable_notes อยู่ใน publication supabase_realtime อยู่แล้ว';
  end if;
end $$;

-- ตรวจผลเบื้องต้น: ต้องได้ PASS ทุกช่อง (ชุดตรวจเต็มอยู่ใน supabase/tests/v1_checks.sql)
select
  x.tablename                                                         as "ตาราง",
  case when c.relrowsecurity then 'PASS' else 'FAIL (RLS ปิดอยู่)' end as "rls",
  case
    when x.tablename = 'app_feedback' then 'ไม่ต้องเปิด'
    when pt.tablename is null then 'FAIL (ไม่อยู่ใน publication)'
    else 'PASS'
  end                                                                 as "realtime",
  case
    when exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = x.tablename and p.cmd in ('UPDATE', 'DELETE', 'ALL')
    ) then 'FAIL (มี policy แก้/ลบ)'
    else 'PASS (append-only)'
  end                                                                 as "ห้ามแก้ห้ามลบ"
from (values ('receivable_notes'), ('app_feedback')) as x(tablename)
join pg_class c on c.oid = ('public.' || x.tablename)::regclass
left join pg_publication_tables pt
  on pt.pubname = 'supabase_realtime'
 and pt.schemaname = 'public'
 and pt.tablename = x.tablename
order by x.tablename;
