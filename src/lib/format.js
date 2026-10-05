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

// ผลรวมของ string เงิน (numeric(14,2)) → string "12345.67"
export function sumMoney(values) {
  const total = values.reduce((acc, v) => acc + toSatang(v), 0n)
  const neg = total < 0n
  const abs = neg ? -total : total
  return (neg ? '-' : '') + (abs / 100n).toString() + '.' + (abs % 100n).toString().padStart(2, '0')
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

// error จาก supabase-js → key ของ i18n
export function loadErrorKey(error) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'eOffline'
  const msg = String(error?.message ?? '')
  if (/Failed to fetch|NetworkError|Load failed|network/i.test(msg)) return 'eOffline'
  if (error?.code === '42501' || error?.code === 'PGRST301' || /permission denied/i.test(msg)) return 'ePermission'
  return 'eLoad'
}
