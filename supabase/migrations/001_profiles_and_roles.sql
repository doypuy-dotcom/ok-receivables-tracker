-- 001_profiles_and_roles.sql — M1
-- enum user_role, ตาราง profiles (schema.md 3.1), RLS + policy, function public.my_role()
-- รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว (ต้องการเปลี่ยน → เขียน 002_*.sql)

-- ---------------------------------------------------------------------------
-- 1. enum
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('owner', 'sales');

-- ---------------------------------------------------------------------------
-- 2. profiles — 1 แถวต่อ 1 บัญชีใน auth.users
--    ไม่มี on delete cascade: ห้ามลบผู้ใช้ ใช้ is_active = false แทน
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id),
  display_name text not null,
  role         public.user_role not null,
  is_active    boolean not null default true,
  created_at   timestamptz default now()
);

comment on table public.profiles is 'ผู้ใช้ของระบบ: ชื่อที่แสดง + role. สร้างและแก้จาก Supabase dashboard / SQL Editor เท่านั้น';

-- ---------------------------------------------------------------------------
-- 3. my_role() — role ของผู้ใช้ที่ล็อกอินอยู่ (null ถ้าไม่มี profile หรือ is_active = false)
--    security definer: อ่าน profiles โดยไม่ผ่าน RLS จึงใช้ใน policy ของ profiles ได้โดยไม่วนซ้ำ
--    search_path = '' : ทุกชื่อต้องระบุ schema เต็ม กันการแอบสร้าง object ชื่อซ้ำ
-- ---------------------------------------------------------------------------
create function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active
$$;

revoke execute on function public.my_role() from public, anon;
grant execute on function public.my_role() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
--    อ่าน: ผู้ใช้ที่ล็อกอินและ is_active (owner, sales) อ่านได้ทุกแถว
--    ไม่มี policy INSERT / UPDATE / DELETE → ผู้ใช้แก้ role ตัวเองไม่ได้ และลบไม่ได้
--    เพิ่ม/แก้ profiles ทำจาก SQL Editor (role postgres) เท่านั้น
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "profiles_select_active_users"
  on public.profiles
  for select
  to authenticated
  using ((select public.my_role()) is not null);

-- ตัดสิทธิ์ระดับตารางเพิ่มอีกชั้น (Supabase ให้สิทธิ์ทุกอย่างกับ anon/authenticated เป็นค่าเริ่มต้น)
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
