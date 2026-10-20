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
  // role ใช้ติดป้าย "เจ้าของ / ฝ่ายขาย" ให้หมายเหตุแต่ละรายการ (V2 ข้อ 2 — migration 007)
  return supabase.from('profiles').select('id,display_name,role').in('id', ids)
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
// **V2 ข้อ 2: เจ้าของเขียนได้ด้วย** (migration 007 — เดิมเขียนได้แค่ฝ่ายขาย) สิทธิ์จริงอยู่ที่ RLS
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
// created_by_role มาจาก view (007): หน้าตารางไม่ได้อ่าน profiles จึงไม่ต้องขอเพิ่มอีก 1 คำขอ
export function fetchLatestNotes() {
  return supabase.from('receivable_latest_note').select('receivable_id,body,created_at,created_by_role')
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

// ---------------------------------------------------------------------------
// หน้าสถิติ (V2 — schema.md 4.5, migration 008)
// อ่านอย่างเดียว ทั้ง owner และ sales · **ยอดเงิน / % / ค่าเฉลี่ย / การจัดกลุ่ม / ลำดับ
// คำนวณใน view ทั้งหมด** แอปแค่เลือกแถวของเดือนที่ดู เลือกแสดง 5 อันดับแรก และจัดรูปแบบ
// (ห้ามบวก / หาร / เทียบเงินหรือ % ใน JS แม้แต่ความกว้างของแถบ — AGENTS.md)
// เงินและ % ขอเป็น text เหมือนทุกหน้า เพื่อไม่ให้ JSON แปลงเป็น float
// ---------------------------------------------------------------------------

// ภาพรวม 1 แถว: ยอดค้าง / ยอดเลยกำหนด ณ วันนี้ + data_since = วันของการ์ดใบแรกสุด
// (บรรทัดบอกข้อจำกัดบนหน้าใช้ data_since ไม่ฮาร์ดโค้ดวันที่ไว้ในแอป)
export function fetchStatsOverview() {
  return supabase
    .from('stats_overview')
    .select(
      'today,data_since,company_count,card_count,outstanding_total::text,outstanding_card_count,overdue_total::text,overdue_card_count',
    )
    .maybeSingle()
}

// ส่วน 1: เก็บเงินของเดือนนั้นได้กี่ % — 1 แถวต่อ 1 เดือนครบกำหนด
// โหลดทุกเดือนครั้งเดียวเหมือนหน้ารายงาน แล้วเลือกแถวของเดือนที่ผู้ใช้กด
// เดือนที่ไม่มีการ์ดเลยจะไม่มีแถว → หน้าจอแสดงสถานะว่าง ไม่ใช่เขียนเลข 0 เอง
export function fetchStatsMonths() {
  return supabase
    .from('stats_collection_by_month')
    .select('due_month,card_count,paid_card_count,due_total::text,collected_total::text,balance_total::text,collected_pct::text')
    .order('due_month')
}

// ส่วน 2: อายุหนี้ค้าง ณ วันนี้ — 4 แถวคงที่เสมอ เรียงตาม bucket_order ของ view
export function fetchStatsAging() {
  return supabase
    .from('stats_aging')
    .select('bucket,bucket_order,balance_total::text,card_count,pct_of_outstanding::text')
    .order('bucket_order')
}

// ส่วน 3: พฤติกรรมการจ่ายต่อบริษัท — เรียงตาม seq ของ view (ช้าสุดก่อน, ข้อมูลน้อยไปท้าย)
export function fetchStatsBehavior() {
  return supabase
    .from('stats_company_behavior')
    .select(
      'seq,company_id,company_name,card_count,paid_card_count,on_time_count,late_card_count,on_time_pct::text,avg_late_days::text,max_late_days,overdue_now_count,overdue_now_total::text,open_card_count,open_total::text,is_thin',
    )
    .order('seq')
}

// ส่วน 4: ยอดค้างกระจุกที่ใคร — view ส่งทุกบริษัทที่ยังค้าง เรียงมาก → น้อย
// แอปแสดง 5 อันดับแรก (seq <= 5) และใช้ cum_pct ของแถวสุดท้ายที่แสดงเป็นสัดส่วนรวมของกลุ่มนั้น
export function fetchStatsBalance() {
  return supabase
    .from('stats_company_balance')
    .select('seq,company_id,company_name,balance_total::text,open_card_count,overdue_card_count,pct_of_outstanding::text,cum_pct::text')
    .order('seq')
}
