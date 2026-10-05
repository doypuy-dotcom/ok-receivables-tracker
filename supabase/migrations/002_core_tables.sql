-- 002_core_tables.sql — M2
-- enums payment_method / audit_action, ตาราง companies / receivables / payments / audit_logs (schema.md 3.2–3.5),
-- RLS + policy (schema.md 5), trigger (meta, กฎยอดเงิน, audit), view receivable_summary (schema.md 4)
-- ต้องรัน 001_profiles_and_roles.sql ก่อน (ใช้ public.my_role() และ public.profiles)
-- รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว (ต้องการเปลี่ยน → เขียน 003_*.sql)
--
-- ข้อความ error ของกฎธุรกิจ (ให้แอปแปลเป็นภาษาคนใน M4):
--   42501 not_authenticated       เขียนข้อมูลโดยไม่มีผู้ใช้ล็อกอิน (auth.uid() ว่าง)
--   23514 payments_exceed_total   ยอดจ่ายรวม (ไม่นับที่ยกเลิก) เกิน total_amount
--   23514 total_below_paid        แก้ total_amount ให้ต่ำกว่ายอดที่จ่ายแล้ว
--   23514 receivable_cancelled    เพิ่มการจ่ายในการ์ดที่ถูกยกเลิก
--   23514 payment_receivable_immutable   เปลี่ยน receivable_id ของการจ่ายที่สร้างแล้ว (ผิดการ์ด → ยกเลิกแล้วสร้างใหม่)
--   23514 companies_name_trimmed  ชื่อบริษัทว่าง / มีแต่ช่องว่าง / มีช่องว่างหน้าหรือหลัง (ชื่อ constraint)
--   23505 receivables_one_per_company_month / companies_name_key   ซ้ำ (ชื่อ constraint)

-- ---------------------------------------------------------------------------
-- 1. enums
-- ---------------------------------------------------------------------------
create type public.payment_method as enum ('transfer', 'cheque');
create type public.audit_action   as enum ('create', 'update', 'cancel');

-- ---------------------------------------------------------------------------
-- 2. ตาราง
--    created_by / updated_by → profiles(id) เหมือน audit_logs.user_id
--    created_* / updated_* ถูกใส่โดย trigger (ข้อ 3) ค่าที่ส่งมาจากแอปจะถูกเขียนทับ
--    ไม่มี on delete cascade ที่ไหนเลย: ห้ามลบ ใช้ is_cancelled / is_active
-- ---------------------------------------------------------------------------
create table public.companies (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles (id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles (id),
  -- ห้ามว่าง ห้ามมีแต่ช่องว่าง ห้ามมีช่องว่างหน้า/หลัง (กัน "บ.X" กับ "บ.X " เป็น 2 บริษัท)
  constraint companies_name_trimmed check (name = btrim(name) and name <> '')
);

comment on table public.companies is 'รายชื่อบริษัทลูกค้า (สาขาแยกชื่อกัน เช่น บ.X 1, บ.X 2)';

create table public.receivables (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies (id),
  account_month     date not null,
  total_amount      numeric(14,2) not null,
  credit_days       integer not null,
  credit_start_date date not null,
  actual_start_date date not null,
  actual_due_date   date not null,
  is_cancelled      boolean not null default false,
  created_at        timestamptz not null default now(),
  created_by        uuid not null references public.profiles (id),
  updated_at        timestamptz not null default now(),
  updated_by        uuid not null references public.profiles (id),
  constraint receivables_account_month_first_day check (extract(day from account_month) = 1),
  constraint receivables_total_amount_positive   check (total_amount > 0),
  constraint receivables_credit_days_positive    check (credit_days > 0),
  constraint receivables_due_after_start         check (actual_due_date >= actual_start_date)
);

comment on table public.receivables is 'การ์ดยอดค้าง: 1 บริษัท + 1 บัญชีเดือน (ไม่นับที่ยกเลิก)';

create unique index receivables_one_per_company_month
  on public.receivables (company_id, account_month) where not is_cancelled;

create table public.payments (
  id            uuid primary key default gen_random_uuid(),
  receivable_id uuid not null references public.receivables (id),
  amount        numeric(14,2) not null,
  method        public.payment_method not null,
  paid_date     date not null,
  paid_time     time not null,
  is_cancelled  boolean not null default false,
  created_at    timestamptz not null default now(),
  created_by    uuid not null references public.profiles (id),
  updated_at    timestamptz not null default now(),
  updated_by    uuid not null references public.profiles (id),
  constraint payments_amount_positive check (amount > 0)
);

comment on table public.payments is 'การจ่ายของการ์ด: โอน = วันที่เงินเข้า, เช็ค = วันที่เช็คขึ้นเงิน';

-- รวมยอดจ่ายต่อการ์ด (trigger + view) ใช้ index นี้
create index payments_receivable_id_idx on public.payments (receivable_id);

create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id),
  action        public.audit_action not null,
  table_name    text not null,
  record_id     uuid not null,
  receivable_id uuid references public.receivables (id),
  old_value     jsonb,
  new_value     jsonb not null,
  created_at    timestamptz not null default now(),
  constraint audit_logs_table_name_valid check (table_name in ('companies', 'receivables', 'payments'))
);

comment on table public.audit_logs is 'ประวัติการแก้ไข เขียนโดย trigger เท่านั้น ห้ามแก้ ห้ามลบ';

-- หน้ารายละเอียดการ์ดอ่านประวัติตามการ์ด เรียงตามเวลา
create index audit_logs_receivable_id_idx on public.audit_logs (receivable_id, created_at);

-- ---------------------------------------------------------------------------
-- 3. trigger functions
--    search_path = '' : ทุกชื่อต้องระบุ schema เต็ม (เหมือน my_role())
--    ลำดับ trigger ในตารางเดียวกันเรียงตามชื่อ: trg_10_* → trg_20_* → trg_90_*
-- ---------------------------------------------------------------------------

-- 3.1 created_* / updated_* อัตโนมัติ + ปฏิเสธการเขียนที่ไม่มีผู้ใช้ล็อกอิน
--     ไม่ใช่ security definer: ไม่ได้อ่านหรือเขียนตารางอื่น
--     ตอน update: id, created_at, created_by คงค่าเดิมเสมอ (แก้ผ่าน API ไม่ได้)
create function public.set_row_meta()
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
            detail  = 'ต้องล็อกอินก่อนเขียนข้อมูล (audit_logs ต้องรู้ว่าใครทำ)';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := v_user;
  else
    new.id         := old.id;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
  end if;

  new.updated_at := now();
  new.updated_by := v_user;
  return new;
end
$$;

-- 3.2 payments: ห้ามเปลี่ยน receivable_id + ยอดจ่ายรวมต้องไม่เกิน total_amount + ห้ามเพิ่มการจ่ายในการ์ดที่ยกเลิก
--     security definer: รวมยอดจากทุกแถวจริง ไม่ขึ้นกับ RLS ของคนที่เรียก
--     for update: ล็อกแถวการ์ด กัน 2 คนบันทึกพร้อมกันแล้วยอดรวมเกิน (และกันชนกับการแก้ total_amount)
create function public.check_payment_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total        numeric(14,2);
  v_cancelled    boolean;
  v_paid_others  numeric(14,2);
begin
  -- การจ่ายอยู่การ์ดเดิมตลอด: ใส่ผิดการ์ด → ยกเลิกแล้วสร้างใหม่ (ประวัติของทั้ง 2 การ์ดจึงครบ)
  if tg_op = 'UPDATE' and new.receivable_id <> old.receivable_id then
    raise exception 'payment_receivable_immutable'
      using errcode = 'check_violation',
            detail  = 'ย้ายการจ่ายไปการ์ดอื่นไม่ได้ ให้ยกเลิกแล้วสร้างใหม่ในการ์ดที่ถูกต้อง';
  end if;

  select r.total_amount, r.is_cancelled
    into v_total, v_cancelled
  from public.receivables r
  where r.id = new.receivable_id
  for update;

  if not found then
    return new;  -- ไม่มีการ์ดนี้ → foreign key ปฏิเสธเอง
  end if;

  -- "เพิ่ม" การจ่ายในการ์ดที่ยกเลิก = insert หรือเลิกยกเลิกการจ่ายในการ์ดนั้น
  -- (แก้ / ยกเลิกการจ่ายเดิมที่อยู่ในการ์ดนั้นอยู่แล้วยังทำได้)
  if v_cancelled and (
       tg_op = 'INSERT'
       or (old.is_cancelled and not new.is_cancelled)
     ) then
    raise exception 'receivable_cancelled'
      using errcode = 'check_violation',
            detail  = 'การ์ดนี้ถูกยกเลิกแล้ว เพิ่มการจ่ายไม่ได้';
  end if;

  if not new.is_cancelled then
    -- ไม่นับแถวของตัวเอง: ตอนแก้ไข ยอดเดิมของการจ่ายนี้ต้องไม่ถูกนับซ้ำ
    select coalesce(sum(p.amount), 0)
      into v_paid_others
    from public.payments p
    where p.receivable_id = new.receivable_id
      and not p.is_cancelled
      and p.id <> new.id;

    if v_paid_others + new.amount > v_total then
      raise exception 'payments_exceed_total'
        using errcode = 'check_violation',
              detail  = format('ยอดรวม %s จ่ายแล้ว %s คงเหลือ %s แต่บันทึก %s',
                               v_total, v_paid_others, v_total - v_paid_others, new.amount);
    end if;
  end if;

  return new;
end
$$;

-- 3.3 receivables: ห้ามแก้ total_amount ให้ต่ำกว่ายอดที่จ่ายแล้ว (ไม่นับการจ่ายที่ยกเลิก)
--     แถวการ์ดถูกล็อกโดย update อยู่แล้ว การบันทึกการจ่ายพร้อมกันจะรอจนเสร็จ
create function public.check_receivable_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_paid numeric(14,2);
begin
  if new.total_amount < old.total_amount then
    select coalesce(sum(p.amount), 0)
      into v_paid
    from public.payments p
    where p.receivable_id = new.id
      and not p.is_cancelled;

    if new.total_amount < v_paid then
      raise exception 'total_below_paid'
        using errcode = 'check_violation',
              detail  = format('จ่ายแล้ว %s ตั้งยอดรวมเป็น %s ไม่ได้', v_paid, new.total_amount);
    end if;
  end if;

  return new;
end
$$;

-- 3.4 audit_logs: 1 แถวต่อทุก insert / update บน 3 ตารางหลัก
--     security definer: ผู้ใช้ไม่มีสิทธิ์ insert audit_logs เอง มีแต่ trigger นี้ที่เขียนได้
--     action: insert = create, is_cancelled false → true = cancel, นอกนั้น = update
--             (companies ไม่มี is_cancelled: ปิด is_active = update)
--     receivable_id: receivables = id ตัวเอง, payments = receivable_id (เปลี่ยนไม่ได้), companies = null
create function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_new    jsonb := to_jsonb(new);
  v_old    jsonb;
  v_action public.audit_action;
begin
  if v_user is null then
    raise exception 'not_authenticated'
      using errcode = 'insufficient_privilege',
            detail  = 'ต้องล็อกอินก่อนเขียนข้อมูล (audit_logs ต้องรู้ว่าใครทำ)';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'create';
  else
    v_old := to_jsonb(old);
    if not coalesce((v_old ->> 'is_cancelled')::boolean, false)
       and coalesce((v_new ->> 'is_cancelled')::boolean, false) then
      v_action := 'cancel';
    else
      v_action := 'update';
    end if;
  end if;

  insert into public.audit_logs (user_id, action, table_name, record_id, receivable_id, old_value, new_value)
  values (
    v_user,
    v_action,
    tg_table_name,
    (v_new ->> 'id')::uuid,
    case tg_table_name
      when 'receivables' then (v_new ->> 'id')::uuid
      when 'payments'    then (v_new ->> 'receivable_id')::uuid
    end,
    v_old,
    v_new
  );

  return null;
end
$$;

-- trigger functions ถูกเรียกโดย trigger เท่านั้น ไม่ต้องให้ใครเรียกตรง
revoke execute on function public.set_row_meta()           from public, anon, authenticated;
revoke execute on function public.check_payment_rules()    from public, anon, authenticated;
revoke execute on function public.check_receivable_total() from public, anon, authenticated;
revoke execute on function public.write_audit_log()        from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. triggers
-- ---------------------------------------------------------------------------
create trigger trg_10_set_meta
  before insert or update on public.companies
  for each row execute function public.set_row_meta();
create trigger trg_90_audit_log
  after insert or update on public.companies
  for each row execute function public.write_audit_log();

create trigger trg_10_set_meta
  before insert or update on public.receivables
  for each row execute function public.set_row_meta();
create trigger trg_20_check_total
  before update on public.receivables
  for each row execute function public.check_receivable_total();
create trigger trg_90_audit_log
  after insert or update on public.receivables
  for each row execute function public.write_audit_log();

create trigger trg_10_set_meta
  before insert or update on public.payments
  for each row execute function public.set_row_meta();
create trigger trg_20_check_rules
  before insert or update on public.payments
  for each row execute function public.check_payment_rules();
create trigger trg_90_audit_log
  after insert or update on public.payments
  for each row execute function public.write_audit_log();

-- ---------------------------------------------------------------------------
-- 5. RLS (schema.md 5)
--    อ่าน: ผู้ใช้ที่ล็อกอินและ is_active (owner, sales) — my_role() เป็น null ถ้าไม่ active
--    เพิ่ม / แก้ไข: sales เท่านั้น (companies, receivables, payments)
--    audit_logs: อ่านอย่างเดียว ไม่มี policy INSERT / UPDATE / DELETE (trigger เขียนแทน)
--    ไม่มี policy DELETE บนตารางไหนเลย
-- ---------------------------------------------------------------------------
alter table public.companies   enable row level security;
alter table public.receivables enable row level security;
alter table public.payments    enable row level security;
alter table public.audit_logs  enable row level security;

create policy "companies_select_active_users"
  on public.companies for select to authenticated
  using ((select public.my_role()) is not null);
create policy "companies_insert_sales"
  on public.companies for insert to authenticated
  with check ((select public.my_role()) = 'sales');
create policy "companies_update_sales"
  on public.companies for update to authenticated
  using ((select public.my_role()) = 'sales')
  with check ((select public.my_role()) = 'sales');

create policy "receivables_select_active_users"
  on public.receivables for select to authenticated
  using ((select public.my_role()) is not null);
create policy "receivables_insert_sales"
  on public.receivables for insert to authenticated
  with check ((select public.my_role()) = 'sales');
create policy "receivables_update_sales"
  on public.receivables for update to authenticated
  using ((select public.my_role()) = 'sales')
  with check ((select public.my_role()) = 'sales');

create policy "payments_select_active_users"
  on public.payments for select to authenticated
  using ((select public.my_role()) is not null);
create policy "payments_insert_sales"
  on public.payments for insert to authenticated
  with check ((select public.my_role()) = 'sales');
create policy "payments_update_sales"
  on public.payments for update to authenticated
  using ((select public.my_role()) = 'sales')
  with check ((select public.my_role()) = 'sales');

create policy "audit_logs_select_active_users"
  on public.audit_logs for select to authenticated
  using ((select public.my_role()) is not null);

-- สิทธิ์ระดับตารางอีกชั้น: ไม่มี DELETE ให้ใคร, anon ไม่ได้อะไรเลย
revoke all on table public.companies, public.receivables, public.payments, public.audit_logs from anon, authenticated;
grant select, insert, update on table public.companies, public.receivables, public.payments to authenticated;
grant select on table public.audit_logs to authenticated;

-- ---------------------------------------------------------------------------
-- 6. view receivable_summary (schema.md 4) — เฉพาะการ์ดที่ไม่ถูกยกเลิก
--    security_invoker = true: ใช้ RLS ของคนที่อ่าน (ไม่งั้น view จะอ่านด้วยสิทธิ์เจ้าของ view และข้าม RLS)
--    วันนี้ = (now() at time zone 'Asia/Bangkok')::date
--    % ทั้งหมดเป็นเลข 0–100 ตัดทศนิยมเหลือ 2 ตำแหน่ง (trunc ไม่ปัด: 99.999% จะไม่กลายเป็น 100%)
-- ---------------------------------------------------------------------------
create view public.receivable_summary
with (security_invoker = true)
as
select
  r.id,
  r.company_id,
  c.name                                            as company_name,
  r.account_month,
  r.total_amount,
  r.credit_days,
  r.credit_start_date,
  r.actual_start_date,
  r.actual_due_date,
  r.created_at,
  r.created_by,
  r.updated_at,
  r.updated_by,
  d.credit_due_date,
  p.paid_amount,
  d.balance,
  d.balance = 0                                     as is_paid,
  case when d.balance = 0 then p.last_paid_date end as paid_in_full_date,
  d.due_month,
  d.balance <> 0 and d.due_month < date_trunc('month', t.today::timestamp)::date
                                                    as is_carried_over,
  r.actual_due_date - t.today                       as days_to_actual_due,
  d.credit_due_date - t.today                       as days_to_credit_due,
  case
    -- วันเริ่ม = วันครบกำหนด (หารด้วย 0): ถึงวันนั้นแล้ว = 100% ยังไม่ถึง = 0%
    when r.actual_due_date = r.actual_start_date then
      case when t.today >= r.actual_due_date then 100 else 0 end
    else
      trunc(least(greatest(
        (t.today - r.actual_start_date)::numeric / (r.actual_due_date - r.actual_start_date),
        0), 1) * 100, 2)
  end::numeric(5,2)                                 as actual_pct,
  trunc(least(greatest(
    (t.today - r.credit_start_date)::numeric / r.credit_days,
    0), 1) * 100, 2)::numeric(5,2)                  as credit_pct,
  trunc(p.paid_amount / r.total_amount * 100, 2)::numeric(5,2)
                                                    as money_pct
from public.receivables r
join public.companies c on c.id = r.company_id
cross join lateral (
  select (now() at time zone 'Asia/Bangkok')::date as today
) t
cross join lateral (
  select coalesce(sum(pm.amount), 0)::numeric(14,2) as paid_amount,
         max(pm.paid_date)                          as last_paid_date
  from public.payments pm
  where pm.receivable_id = r.id
    and not pm.is_cancelled
) p
cross join lateral (
  select r.credit_start_date + r.credit_days                 as credit_due_date,
         (r.total_amount - p.paid_amount)::numeric(14,2)     as balance,
         date_trunc('month', r.actual_due_date::timestamp)::date as due_month
) d
where not r.is_cancelled;

comment on view public.receivable_summary is 'การ์ดที่ไม่ถูกยกเลิก + ค่าคำนวณทั้งหมด (schema.md 4) แอปอ่านจาก view นี้เท่านั้น ห้ามคำนวณเงินเอง';

revoke all on table public.receivable_summary from anon, authenticated;
grant select on table public.receivable_summary to authenticated;
