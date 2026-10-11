// จัดรูปแบบเงิน / วันที่ / % สำหรับแสดงผลเท่านั้น — ค่าทุกตัวคำนวณมาจาก receivable_summary แล้ว
// เงินรับเป็น string จาก database (select `balance::text`) และจัดรูปแบบด้วย string ไม่แปลงเป็น float
// การบวกยอดรวมของหลายการ์ด (กล่องยอดรวม) ใช้ BigInt หน่วยสตางค์ ได้ผลตรงตัว

const LOCALE = { th: 'th-TH', en: 'en-GB' }
const TZ = 'Asia/Bangkok'

// "-1234567.5" / -1234567.5 → "-1,234,567.50"
export function money(value) {
  if (value === null || value === undefined || value === '') return '–'
  const s = String(value)
  const neg = s.startsWith('-')
  const [int, frac = ''] = (neg ? s.slice(1) : s).split('.')
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return (neg ? '-' : '') + grouped + '.' + (frac + '00').slice(0, 2)
}

function toSatang(value) {
  const s = String(value)
  const neg = s.startsWith('-')
  const [int, frac = ''] = (neg ? s.slice(1) : s).split('.')
  const n = BigInt(int || '0') * 100n + BigInt((frac + '00').slice(0, 2))
  return neg ? -n : n
}

function fromSatang(total) {
  const neg = total < 0n
  const abs = neg ? -total : total
  return (neg ? '-' : '') + (abs / 100n).toString() + '.' + (abs % 100n).toString().padStart(2, '0')
}

// ผลรวมของ string เงิน (numeric(14,2)) → string "12345.67"
export function sumMoney(values) {
  return fromSatang(values.reduce((acc, v) => acc + toSatang(v), 0n))
}

// บวกเงิน 2 ค่าแบบตรงตัว (หน่วยสตางค์) — ใช้หายอดที่ยังบันทึกได้ตอนแก้ไขการจ่าย
export function addMoney(a, b) {
  return fromSatang(toSatang(a) + toSatang(b))
}

// เทียบเงิน 2 ค่า: -1 = a น้อยกว่า, 0 = เท่ากัน, 1 = a มากกว่า (ไม่ใช้ float)
export function cmpMoney(a, b) {
  const x = toSatang(a)
  const y = toSatang(b)
  return x < y ? -1 : x > y ? 1 : 0
}

// ข้อความเงินที่ยอมรับจากฟอร์ม: ตัวเลขบวก ทศนิยมไม่เกิน 2 ตำแหน่ง (เก็บเป็น string ไม่แปลงเป็น float)
export function isMoneyText(s) {
  return /^\d+(\.\d{1,2})?$/.test(String(s).trim())
}

// % จาก view เป็น string "0.00"–"100.00" ตัดทศนิยมแล้ว → แสดงเลขเต็ม (99.99 → "99" ไม่ปัดเป็น 100)
export function pctLabel(value) {
  return String(value ?? '0').split('.')[0]
}

const utc = (iso) => new Date(Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)))

// "2026-10-06" → "อ. 6 ต.ค. 2569" (พ.ศ. ในภาษาไทย)
export function fmtDate(lang, iso, weekday = false) {
  if (!iso) return '–'
  return utc(iso).toLocaleDateString(LOCALE[lang], {
    timeZone: 'UTC',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    ...(weekday ? { weekday: 'short' } : {}),
  })
}

// "2026-10-01" หรือ "2026-10" → "ตุลาคม 2569" / "ต.ค. 2569"
export function fmtMonth(lang, iso, long = false) {
  if (!iso) return '–'
  return utc(iso.length === 7 ? iso + '-01' : iso).toLocaleDateString(LOCALE[lang], {
    timeZone: 'UTC',
    month: long ? 'long' : 'short',
    year: 'numeric',
  })
}

// "13:30:00" → "13:30 น."
export function fmtTime(lang, time) {
  if (!time) return ''
  return time.slice(0, 5) + (lang === 'th' ? ' น.' : '')
}

// timestamptz → "6 ต.ค. 2569 21:15 น." ตามเวลาไทย
export function fmtStamp(lang, ts) {
  if (!ts) return '–'
  const d = new Date(ts)
  const date = d.toLocaleDateString(LOCALE[lang], { timeZone: TZ, day: 'numeric', month: 'short', year: 'numeric' })
  const time = d.toLocaleTimeString('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
  return date + ' ' + time + (lang === 'th' ? ' น.' : '')
}

// เดือนปัจจุบันตามเวลาไทย "YYYY-MM-01" — ใช้เป็นค่าเริ่มต้นของตัวกรองเดือนเท่านั้น (ค่าคำนวณทั้งหมดใช้วันนี้จาก database)
export function currentMonthBangkok() {
  const ymd = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(
    new Date(),
  )
  return ymd.slice(0, 7) + '-01'
}

// เดือนก่อนตามเวลาไทย "YYYY-MM" — ค่าเริ่มต้นของช่อง "บัญชีเดือน" (ใบวางบิลมักเป็นของเดือนที่ผ่านมา
// เหมือนค่าเริ่มต้นใน ui-reference) ผู้ใช้เปลี่ยนได้
export function previousMonthBangkok() {
  const d = utc(currentMonthBangkok())
  d.setUTCMonth(d.getUTCMonth() - 1)
  return d.toISOString().slice(0, 7)
}

// "2026-10-06" + 60 → "2026-12-05" — ใช้แสดงตัวอย่าง "ครบกำหนดเครดิต" ในฟอร์มเท่านั้น
// ค่าจริงที่แอปแสดงหลังบันทึกมาจาก receivable_summary.credit_due_date ของ database
export function addDays(iso, days) {
  if (!iso || !Number.isFinite(days)) return null
  const d = utc(iso)
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

// "วันนี้" / "เวลานี้" ตามเวลาไทย — ใช้เป็นค่าเริ่มต้นของช่องกรอกเท่านั้น
export function todayBangkok() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(
    new Date(),
  )
}

export function nowTimeBangkok() {
  return new Date().toLocaleTimeString('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
}

// error จาก supabase-js → key ของ i18n
export function loadErrorKey(error) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'eOffline'
  const msg = String(error?.message ?? '')
  if (/Failed to fetch|NetworkError|Load failed|network/i.test(msg)) return 'eOffline'
  if (error?.code === '42501' || error?.code === 'PGRST301' || /permission denied/i.test(msg)) return 'ePermission'
  return 'eLoad'
}

// ---------------------------------------------------------------------------
// ช่องวันที่ของแอปเอง (V1 รอบ ก) — ดู src/components/DateField.jsx
// ---------------------------------------------------------------------------

const monthNameCache = {}

// ชื่อเดือนแบบเต็มของภาษานั้น ["มกราคม", …] / ["January", …] — ใช้ในช่องเลือกเดือน
export function monthNames(lang) {
  if (!monthNameCache[lang]) {
    const f = new Intl.DateTimeFormat(LOCALE[lang], { timeZone: 'UTC', month: 'long' })
    monthNameCache[lang] = Array.from({ length: 12 }, (_, i) => f.format(Date.UTC(2026, i, 1)))
  }
  return monthNameCache[lang]
}

// ป้ายปีในช่องเลือก: ไทยเป็น พ.ศ. (ค.ศ. + 543) อังกฤษเป็น ค.ศ.
// ค่าที่เก็บในฟอร์มและส่ง database เป็น ค.ศ. เสมอ — พ.ศ. มีแต่ตอนแสดงผล
export function yearLabel(lang, year) {
  return String(lang === 'th' ? Number(year) + 543 : Number(year))
}

// จำนวนวันของเดือน (ปี ค.ศ., เดือน 1–12) — ใช้ตรวจว่าวันที่ที่เลือกมีจริง (31 ก.พ. ไม่มี)
export function daysInMonth(year, month) {
  return new Date(Date.UTC(Number(year), Number(month), 0)).getUTCDate()
}

// ชื่อวันในสัปดาห์แบบเต็มของวันที่นั้น ("ศุกร์" / "Friday")
// ภาษาไทย Intl คืน "วันศุกร์" → ตัด "วัน" หน้าออก เพราะบรรทัดใต้ช่องเขียนว่า "ศุกร์ 9 ตุลาคม 2569"
export function weekdayName(lang, iso) {
  if (!iso) return ''
  const name = new Intl.DateTimeFormat(LOCALE[lang], { timeZone: 'UTC', weekday: 'long' }).format(utc(iso))
  return lang === 'th' ? name.replace(/^วัน/, '') : name
}
