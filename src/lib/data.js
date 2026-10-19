// คำสั่งอ่าน/เขียนข้อมูล — อ่านจาก receivable_summary, payments, audit_logs (+ profiles สำหรับชื่อคนแก้)
// เงินและ % ขอเป็น text (`::text`) เพื่อไม่ให้ JSON แปลงเป็น float
// การเขียน (M4) ส่งเฉพาะช่องที่ผู้ใช้กรอก: created_*/updated_* ใส่โดย trigger, audit_logs เขียนโดย trigger
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

// "ข้อมูล ณ" = เวลาที่ข้อมูลถูกแก้ไขล่าสุด (prd ข้อ 6) อ่านจาก audit_logs
// trigger เขียน audit_logs ทุก insert/update ของ 3 ตารางหลัก จึงครอบคลุมการยกเลิกการ์ด
// (การ์ดที่ยกเลิกหายไปจาก view, การแก้การจ่ายไม่เปลี่ยน updated_at ของการ์ด — ดู progress.md M4)
export function fetchLatestChange() {
  return supabase.from('audit_logs').select('created_at').order('created_at', { ascending: false }).limit(1)
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

// ---------------------------------------------------------------------------
// รายชื่อบริษัท
// ---------------------------------------------------------------------------

// ทุกบริษัทรวมที่ปิดอยู่: รายการเลือกแสดงเฉพาะที่เปิด แต่ชื่อซ้ำต้องเทียบกับทั้งหมด (name เป็น unique)
export function fetchCompanies() {
  return supabase.from('companies').select('id,name,is_active')
}

export function insertCompany(name) {
  return supabase.from('companies').insert({ name }).select('id,name,is_active').single()
}

// ชื่อตรงกับบริษัทที่ถูกปิดไว้ (เช่นหลัง cleanup ข้อมูล [TEST]) → เปิดกลับมาใช้ ไม่สร้างชื่อซ้ำ
export function reactivateCompany(id) {
  return supabase.from('companies').update({ is_active: true }).eq('id', id).select('id')
}

// ---------------------------------------------------------------------------
// การ์ดยอดค้าง / การจ่าย
// update คืน select('id') ด้วย เพื่อรู้ว่า RLS ปล่อยให้แก้จริงไหม (policy ที่ไม่ผ่านคืน 0 แถว ไม่ใช่ error)
// ---------------------------------------------------------------------------

export function insertReceivable(values) {
  return supabase.from('receivables').insert(values).select('id').single()
}

export function updateReceivable(id, values) {
  return supabase.from('receivables').update(values).eq('id', id).select('id')
}

export function cancelReceivable(id) {
  return supabase.from('receivables').update({ is_cancelled: true }).eq('id', id).select('id')
}

export function insertPayment(values) {
  return supabase.from('payments').insert(values).select('id').single()
}

// ไม่มี receivable_id ใน values: การจ่ายอยู่การ์ดเดิมตลอด (schema.md 3.4)
export function updatePayment(id, values) {
  return supabase.from('payments').update(values).eq('id', id).select('id')
}

export function cancelPayment(id) {
  return supabase.from('payments').update({ is_cancelled: true }).eq('id', id).select('id')
}

// ---------------------------------------------------------------------------
// หมายเหตุบนการ์ด (V1 รอบ ข — schema.md 3.6)
// ต่อท้ายอย่างเดียว: มีแต่ insert ไม่มี update / cancel / delete
// created_by / created_at ใส่โดย trigger — แอปส่งแค่ receivable_id กับ body
// ---------------------------------------------------------------------------

// ความยาวสูงสุดของหมายเหตุ = constraint receivable_notes_body_len ใน 005_notes_and_feedback.sql
export const NOTE_MAX_LEN = 1000

// หมายเหตุทุกแถวของการ์ด เรียงใหม่ → เก่า (ทั้ง owner และ sales อ่านได้)
export function fetchNotes(receivableId) {
  return supabase
    .from('receivable_notes')
    .select('id,body,created_by,created_at')
    .eq('receivable_id', receivableId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
}

// หมายเหตุล่าสุด 1 แถวต่อ 1 การ์ด สำหรับการ์ดในหน้าตาราง (schema.md 4.1)
export function fetchLatestNotes() {
  return supabase.from('receivable_latest_note').select('receivable_id,body,created_at')
}

export function insertNote(receivableId, body) {
  return supabase.from('receivable_notes').insert({ receivable_id: receivableId, body }).select('id').single()
}

// ---------------------------------------------------------------------------
// feedback เกี่ยวกับแอป (V1 รอบ ข — schema.md 3.7, prd.md ข้อ 11)
// user_id / role / created_at ใส่โดย trigger · app_version ส่งจาก src/lib/version.js
// อ่านได้แค่แถวของตัวเอง (RLS) และไม่มี update / delete ให้ใคร
// ---------------------------------------------------------------------------

// ความยาวสูงสุดของข้อความ = constraint app_feedback_issues_len ใน 005_notes_and_feedback.sql
export const FEEDBACK_ISSUES_MAX_LEN = 2000

export function insertFeedback(values) {
  return supabase.from('app_feedback').insert(values).select('id').single()
}

// ---------------------------------------------------------------------------
// หน้าสรุปรายเดือน (V2 — schema.md 4.3, migration 006)
// อ่านอย่างเดียว ทั้ง owner และ sales · **ยอดเงินทุกตัวรวมยอดรวมมาจาก view**
// แอปแค่กรองแถวตาม due_month และจัดรูปแบบตัวเลข (ห้ามบวก/เทียบเงินเอง — AGENTS.md)
// โหลดทุกเดือนครั้งเดียวเหมือนหน้าตาราง: บล็อก "ยอดค้างข้ามเดือน" ต้องใช้แถวของเดือนก่อน ๆ ด้วย
// ---------------------------------------------------------------------------

const REPORT_COLUMNS = [
  'due_month',
  'seq',
  'receivable_id',
  'company_name',
  'credit_days',
  'account_month',
  'total_amount::text',
  'balance::text',
  'is_paid',
  'actual_due_date',
].join(',')

export function fetchReportRows() {
  return supabase.from('monthly_report').select(REPORT_COLUMNS).order('due_month').order('seq')
}

// แถว "ยอดรวม" ท้ายตาราง 1 แถวต่อ 1 เดือน (เดือนที่ไม่มีการ์ดจะไม่มีแถว → หน้าจอแสดงสถานะว่าง)
export function fetchReportTotals() {
  return supabase
    .from('monthly_report_total')
    .select('due_month,card_count,total_amount_sum::text,balance_sum::text')
}

// "วันนี้" + เวลาที่ดู ตามเวลาไทยจาก database (ไม่ใช่นาฬิกาเครื่อง ซึ่งตั้งเพี้ยนได้)
export function fetchReportAsOf() {
  return supabase.from('report_asof').select('today,viewed_at').maybeSingle()
}
