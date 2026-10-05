-- 003_summary_paid_late.sql — M3
-- เพิ่ม 2 คอลัมน์ท้าย view receivable_summary สำหรับการ์ดจ่ายแล้ว / หน้าสรุปผล ("ตรงเวลา" / "ช้ากว่ากำหนด N วัน")
--   paid_late_actual_days = paid_in_full_date − actual_due_date   (ว่างถ้ายังจ่ายไม่ครบ, > 0 = ช้า)
--   paid_late_credit_days = paid_in_full_date − credit_due_date
-- ไม่แตะตาราง: คอลัมน์เดิมทุกตัวชื่อ / ชนิด / ลำดับเหมือน 002 (create or replace view เพิ่มคอลัมน์ได้แค่ท้ายสุด)
-- ต้องรัน 002_core_tables.sql ก่อน · รันครั้งเดียวใน Supabase SQL Editor ห้ามแก้ไฟล์นี้หลังรันแล้ว

create or replace view public.receivable_summary
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
                                                    as money_pct,
  -- ใหม่ใน 003: จ่ายครบช้ากว่ากำหนดกี่วัน (ติดลบ / 0 = ตรงเวลา) ว่างถ้ายังจ่ายไม่ครบ
  case when d.balance = 0 then p.last_paid_date - r.actual_due_date end
                                                    as paid_late_actual_days,
  case when d.balance = 0 then p.last_paid_date - d.credit_due_date end
                                                    as paid_late_credit_days
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

-- สิทธิ์เหมือน 002 (create or replace คงสิทธิ์เดิมไว้อยู่แล้ว เขียนซ้ำให้ชัด)
revoke all on table public.receivable_summary from anon, authenticated;
grant select on table public.receivable_summary to authenticated;
