// แปล error จาก database เป็นภาษาคน ตามตารางใน schema.md ข้อ 6
// message ของ trigger (เช่น 'payments_exceed_total') และชื่อ constraint ใน message ของ postgres คงที่ จึงจับได้ตรง ๆ
// ตัวบังคับกฎจริงคือ RLS + trigger การตรวจในฟอร์มเป็นแค่ความสะดวก (architecture.md ข้อ 3)

// ชื่อที่พบใน message → key ของ i18n (เรียงตามลำดับที่ตรวจ: เจาะจงก่อน)
const BY_NAME = [
  ['not_authenticated', 'eNotAuth'],
  ['payments_exceed_total', 'eOverTotal'],
  ['total_below_paid', 'eTotalBelowPaid'],
  // ต้องอยู่ก่อน receivable_cancelled: ชื่อยาวกว่าและมีชื่อสั้นซ้อนอยู่ข้างใน
  ['note_receivable_cancelled', 'eNoteCancelled'],
  ['receivable_cancelled', 'eRecCancelled'],
  ['payment_receivable_immutable', 'ePayMoved'],
  ['companies_name_trimmed', 'eCoName'],
  ['companies_name_key', 'coExists'],
  ['receivables_one_per_company_month', 'eDupCard'],
  ['receivables_account_month_first_day', 'eAcctMonth'],
  ['receivables_total_amount_positive', 'eTotal'],
  ['receivables_credit_days_positive', 'eDays'],
  ['receivables_due_after_start', 'eDue'],
  ['payments_amount_positive', 'eAmt'],
  // หมายเหตุบนการ์ด + feedback (V1 รอบ ข — schema.md 3.6, 3.7)
  ['receivable_notes_body_trimmed', 'eNoteEmpty'],
  ['receivable_notes_body_len', 'eNoteLong'],
  ['app_feedback_helpful_range', 'eFbHelpful'],
  ['app_feedback_owner_question', 'eFbRole'],
  ['app_feedback_sales_question', 'eFbRole'],
  ['app_feedback_asks_range', 'eFbRange'],
  ['app_feedback_minutes_range', 'eFbRange'],
  ['app_feedback_issues_trimmed', 'eFbIssues'],
  ['app_feedback_issues_len', 'eFbIssues'],
]

// error จาก supabase-js ตอน "เขียน" → key ของ i18n (ใช้กับ t())
export function saveErrorKey(error) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'eOffline'
  const msg = String(error?.message ?? '')
  if (/Failed to fetch|NetworkError|Load failed|network/i.test(msg)) return 'eOffline'

  for (const [name, key] of BY_NAME) {
    if (msg.includes(name)) return key
  }

  // 42501 ที่ไม่ใช่ not_authenticated = RLS ปฏิเสธ (role ไม่มีสิทธิ์เขียน)
  if (error?.code === '42501' || /row-level security|permission denied/i.test(msg)) return 'eNoWrite'
  return 'eSave'
}
