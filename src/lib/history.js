// ประวัติการแก้ไขของการ์ด (schema.md 3.5): เลือกรายการที่แสดงได้ และหาช่องที่เปลี่ยน
// ทุก update เขียน audit แม้ค่าไม่เปลี่ยน → รายการที่ไม่มีช่องไหนเปลี่ยนถูกกรองออก

// ช่องที่ trigger เปลี่ยนเองทุกครั้ง ไม่ใช่สิ่งที่ผู้ใช้แก้
const META = new Set(['id', 'created_at', 'created_by', 'updated_at', 'updated_by'])

const FIELD_ORDER = [
  'company_id',
  'account_month',
  'total_amount',
  'credit_days',
  'credit_start_date',
  'actual_start_date',
  'actual_due_date',
  'amount',
  'method',
  'paid_date',
  'paid_time',
  'receivable_id',
  'is_cancelled',
]

const TITLE = {
  'receivables:update': 'hEditRec',
  'receivables:cancel': 'hCancelRec',
  'payments:update': 'hEditPay',
  'payments:cancel': 'hCancelPay',
}

const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null)

// รายการที่แสดงได้ + ช่องที่เปลี่ยน (เรียงตาม FIELD_ORDER)
export function buildHistory(logs) {
  const out = []
  for (const log of logs) {
    const title = TITLE[`${log.table_name}:${log.action}`]
    if (!title) continue
    const oldV = log.old_value ?? {}
    const newV = log.new_value ?? {}
    const keys = [...new Set([...Object.keys(oldV), ...Object.keys(newV)])].filter((k) => !META.has(k))
    let changed = keys.filter((k) => !same(oldV[k], newV[k]))
    if (changed.length === 0) continue
    // ยกเลิก: หัวข้อบอกอยู่แล้ว ไม่ต้องแสดง "สถานะ ใช้งาน → ยกเลิกแล้ว" ซ้ำ
    if (log.action === 'cancel') changed = changed.filter((k) => k !== 'is_cancelled')
    changed.sort((a, b) => FIELD_ORDER.indexOf(a) - FIELD_ORDER.indexOf(b))
    out.push({ log, title, changed, oldV, newV })
  }
  return out
}
