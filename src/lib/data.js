// คำสั่งอ่านข้อมูลของ M3 — อ่านจาก receivable_summary, payments, audit_logs (+ profiles สำหรับชื่อคนแก้)
// เงินและ % ขอเป็น text (`::text`) เพื่อไม่ให้ JSON แปลงเป็น float
import { supabase } from './supabase.js'

const SUMMARY_COLUMNS = [
  'id',
  'company_id',
  'company_name',
  'account_month',
  'total_amount::text',
  'credit_days',
  'credit_start_date',
  'actual_start_date',
  'actual_due_date',
  'updated_at',
  'credit_due_date',
  'paid_amount::text',
  'balance::text',
  'is_paid',
  'paid_in_full_date',
  'due_month',
  'is_carried_over',
  'days_to_actual_due',
  'days_to_credit_due',
  'actual_pct::text',
  'credit_pct::text',
  'money_pct::text',
  'paid_late_actual_days',
  'paid_late_credit_days',
].join(',')

const PAYMENT_COLUMNS = 'id,receivable_id,amount::text,method,paid_date,paid_time,updated_at'

export function fetchSummaries() {
  return supabase.from('receivable_summary').select(SUMMARY_COLUMNS)
}

export function fetchSummary(id) {
  return supabase.from('receivable_summary').select(SUMMARY_COLUMNS).eq('id', id).maybeSingle()
}

// "ข้อมูล ณ": การแก้ไขการจ่าย (รวมที่ยกเลิก) ไม่เปลี่ยน updated_at ของการ์ด จึงต้องดูจาก payments ด้วย
export function fetchLatestPaymentUpdate() {
  return supabase.from('payments').select('updated_at').order('updated_at', { ascending: false }).limit(1)
}

// การจ่ายที่ไม่ถูกยกเลิกของการ์ด เรียงเก่า → ใหม่
export function fetchPayments(receivableId) {
  return supabase
    .from('payments')
    .select(PAYMENT_COLUMNS)
    .eq('receivable_id', receivableId)
    .eq('is_cancelled', false)
    .order('paid_date', { ascending: true })
    .order('paid_time', { ascending: true })
}

// ประวัติการแก้ไขที่แสดงได้ (schema.md 3.5): แก้ไข / ยกเลิก ของการ์ดและการจ่าย ใหม่ → เก่า
export function fetchEditLogs(receivableId) {
  return supabase
    .from('audit_logs')
    .select('id,user_id,action,table_name,record_id,old_value,new_value,created_at')
    .eq('receivable_id', receivableId)
    .in('table_name', ['receivables', 'payments'])
    .in('action', ['update', 'cancel'])
    .order('created_at', { ascending: false })
}

// ชื่อบริษัทเดิมเมื่อการ์ดเปลี่ยนบริษัท: อ่านจาก audit_logs ของ companies (ชื่อล่าสุดของแต่ละ id)
export function fetchCompanyNameLogs(companyIds) {
  return supabase
    .from('audit_logs')
    .select('record_id,new_value,created_at')
    .eq('table_name', 'companies')
    .in('record_id', companyIds)
    .order('created_at', { ascending: true })
}

export function fetchProfiles(ids) {
  return supabase.from('profiles').select('id,display_name').in('id', ids)
}
