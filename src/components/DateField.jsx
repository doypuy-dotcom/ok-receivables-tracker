// ช่องวันที่ของแอปเอง (V1 รอบ ก — แก้ครั้งที่ 2 ตาม feedback ลูกค้า 11 ต.ค. ดู progress.md)
// ลูกค้าไม่เอาแบบ dropdown 3 ช่อง ขอช่องเดียวที่พิมพ์เองได้ + ไอคอนปฏิทิน (เหมือนช่องเดิมของเบราว์เซอร์)
// แต่ลำดับต้องเป็น วว/ดด/ปปปป และชื่อเดือนต้องเป็นภาษาไทย → ทำช่องและปฏิทินเองทั้งหมด
// (ห้ามใช้ input type="date" / type="month" — AGENTS.md) และไม่ลงไลบรารีปฏิทิน
//
//   DateField  : ช่องข้อความ "วว/ดด/ปปปป" + ปฏิทินรายเดือน
//   MonthField : ช่องข้อความ "ดด/ปปปป"   + ตารางเลือกเดือน (บัญชีเดือน)
//
// - พิมพ์ได้แต่ตัวเลข แอปใส่ "/" ให้เองตอนพิมพ์ (พิมพ์ "/" เองก็ได้ กลุ่มที่เลขไม่ครบจะเติม 0 ให้)
// - ปี 4 หลัก: **>= 2400 ถือเป็น พ.ศ.** (ลบ 543 ออก) ต่ำกว่านั้นถือเป็น ค.ศ.
// - ค่าที่รับเข้า/ส่งออกเป็น ISO ค.ศ. เสมอ ('YYYY-MM-DD' / 'YYYY-MM') — พ.ศ. มีแต่ตอนแสดงผล
//   ฟอร์มและ data.js จึงไม่ต้องรู้เรื่อง พ.ศ. เลย
// - พิมพ์ไม่ครบ / วันที่ไม่มีจริง (31 ก.พ.) / ปีเพี้ยน → ส่งค่าว่างออกไป **บันทึกไม่ได้**
//   และบรรทัดใต้ช่องเปลี่ยนเป็นข้อความเตือน (ปกติบรรทัดนี้แสดงวันที่ที่ระบบเข้าใจเป็นคำเต็ม)
// - อังกฤษ: ชื่อเดือนอังกฤษ ปี ค.ศ. แต่ลำดับยังเป็น dd/mm/yyyy เหมือนกัน
import { useEffect, useRef, useState } from 'react'
import { daysInMonth, monthNames, todayBangkok, weekdayName, yearLabel } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

const pad2 = (n) => String(n).padStart(2, '0')

// ความกว้างของแต่ละกลุ่มที่พิมพ์: วัน 2 / เดือน 2 / ปี 4
const DAY_W = [2, 2, 4]
const MONTH_W = [2, 4]

// ปีที่ยอมรับ (หลังแปลงเป็น ค.ศ. แล้ว) — กันพิมพ์ปีผิดจนกลายเป็นปีที่ไม่มีเหตุผล
const MIN_YEAR = 1900
const MAX_YEAR = 2200

// ค.ศ. + 543 ขึ้นไปถือว่าเป็น พ.ศ. (พ.ศ. 2400 = ค.ศ. 1857 — ไม่มีทางปนกับ ค.ศ. ที่ใช้งานจริง)
const BE_FROM = 2400

const total = (widths) => widths.reduce((a, b) => a + b, 0)

// ข้อความที่ผู้ใช้พิมพ์ → ตัวเลขล้วน
// ผู้ใช้พิมพ์ "/" เองได้: กลุ่มที่ปิดด้วย "/" แล้วแต่เลขไม่ครบ จะถูกเติม 0 ข้างหน้า ("9/" → "09/")
function toDigits(raw, widths) {
  const groups = String(raw).split('/')
  let out = ''
  groups.forEach((group, i) => {
    let d = group.replace(/\D/g, '')
    const w = widths[i]
    const closed = i < groups.length - 1
    if (w !== undefined && closed && d.length > 0 && d.length < w) d = d.padStart(w, '0')
    out += d
  })
  return out.slice(0, total(widths))
}

// ตัวเลขล้วน → ข้อความที่มี "/" คั่น · eager = ใส่ "/" ให้ทันทีที่กลุ่มเต็ม (ตอนพิมพ์ ไม่ใช่ตอนลบ)
function mask(digits, widths, eager) {
  const parts = []
  let i = 0
  for (const w of widths) {
    if (i >= digits.length) break
    parts.push(digits.slice(i, i + w))
    i += w
  }
  let s = parts.join('/')
  const last = parts.length - 1
  if (eager && parts.length < widths.length && parts[last]?.length === widths[last]) s += '/'
  return s
}

// ISO ค.ศ. → ข้อความในช่อง (ปีตามภาษา: ไทยเป็น พ.ศ.)
function fromISO(iso, lang, withDay) {
  if (!iso) return ''
  const y = yearLabel(lang, iso.slice(0, 4))
  const m = iso.slice(5, 7)
  return withDay ? `${iso.slice(8, 10)}/${m}/${y}` : `${m}/${y}`
}

// ข้อความในช่อง → { empty } | { err, bad } | { iso, y, m, d }
function parseText(text, widths) {
  const withDay = widths.length === 3
  const digits = toDigits(text, widths)
  if (digits.length === 0) return { empty: true }
  if (digits.length < total(widths)) return { err: withDay ? 'eDateShort' : 'eMonthShort' }

  const d = withDay ? Number(digits.slice(0, 2)) : 1
  const m = Number(withDay ? digits.slice(2, 4) : digits.slice(0, 2))
  const typedYear = Number(digits.slice(withDay ? 4 : 2))
  const y = typedYear >= BE_FROM ? typedYear - 543 : typedYear

  if (y < MIN_YEAR || y > MAX_YEAR) return { err: 'eDateYear' }
  if (m < 1 || m > 12) return { err: 'eDateMonth' }
  const max = daysInMonth(y, m)
  if (withDay && (d < 1 || d > max)) return { err: 'eBadDate', bad: { y, m, max } }

  return { y, m, d, iso: withDay ? `${y}-${pad2(m)}-${pad2(d)}` : `${y}-${pad2(m)}` }
}

function CalIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M3 10h18M8 3v4M16 3v4" />
    </svg>
  )
}

// ปฏิทินของแอปเอง: ชื่อเดือนไทย ปี พ.ศ. วันในสัปดาห์ อา จ อ พ พฤ ศ ส (เริ่มวันอาทิตย์)
// withDay = false → ตารางเลือกเดือน ม.ค.–ธ.ค. ของปีนั้น
function Calendar({ iso, withDay, onPick }) {
  const { t, lang } = useLang()
  const months = monthNames(lang)
  const today = todayBangkok()
  const start = iso || today
  const [view, setView] = useState({ y: Number(start.slice(0, 4)), m: Number(start.slice(5, 7)) })

  const shiftMonth = (by) =>
    setView((v) => {
      const n = v.m - 1 + by
      return { y: v.y + Math.floor(n / 12), m: ((n % 12) + 12) % 12 + 1 }
    })
  const shiftYear = (by) => setView((v) => ({ ...v, y: v.y + by }))

  const title = withDay ? `${months[view.m - 1]} ${yearLabel(lang, view.y)}` : yearLabel(lang, view.y)

  const head = (
    <div className="cal-h">
      <button type="button" className="cal-nav" aria-label={t('dPrevY')} onClick={() => shiftYear(-1)}>
        «
      </button>
      {withDay && (
        <button type="button" className="cal-nav" aria-label={t('dPrevM')} onClick={() => shiftMonth(-1)}>
          ‹
        </button>
      )}
      <span className="cal-t" aria-live="polite">
        {title}
      </span>
      {withDay && (
        <button type="button" className="cal-nav" aria-label={t('dNextM')} onClick={() => shiftMonth(1)}>
          ›
        </button>
      )}
      <button type="button" className="cal-nav" aria-label={t('dNextY')} onClick={() => shiftYear(1)}>
        »
      </button>
    </div>
  )

  if (!withDay) {
    return (
      <div className="cal" role="group" aria-label={t('dOpenMonth')}>
        {head}
        <div className="cal-m">
          {months.map((name, i) => {
            const value = `${view.y}-${pad2(i + 1)}`
            return (
              <button
                key={name}
                type="button"
                className={'cal-d' + (value === iso ? ' sel' : '') + (value === today.slice(0, 7) ? ' today' : '')}
                aria-label={`${name} ${yearLabel(lang, view.y)}`}
                onClick={() => onPick(value)}
              >
                {name}
              </button>
            )
          })}
        </div>
      </div>
    )
  }

  // ช่องว่างหน้าวันที่ 1 ให้ตรงคอลัมน์วันในสัปดาห์ (getUTCDay: 0 = อาทิตย์)
  const lead = new Date(Date.UTC(view.y, view.m - 1, 1)).getUTCDay()
  const days = daysInMonth(view.y, view.m)

  return (
    <div className="cal" role="group" aria-label={t('dOpenCal')}>
      {head}
      <div className="cal-grid">
        {t('dWeekdays')
          .split(' ')
          .map((w, i) => (
            <span key={w + i} className="cal-wd" aria-hidden="true">
              {w}
            </span>
          ))}
        {Array.from({ length: lead }, (_, i) => (
          <span key={`b${i}`} />
        ))}
        {Array.from({ length: days }, (_, i) => {
          const d = i + 1
          const value = `${view.y}-${pad2(view.m)}-${pad2(d)}`
          return (
            <button
              key={d}
              type="button"
              className={'cal-d' + (value === iso ? ' sel' : '') + (value === today ? ' today' : '')}
              aria-label={`${d} ${months[view.m - 1]} ${yearLabel(lang, view.y)}`}
              aria-current={value === today ? 'date' : undefined}
              onClick={() => onPick(value)}
            >
              {d}
            </button>
          )
        })}
      </div>
    </div>
  )
}

function Field({ id, label, hint, value, onChange, withDay }) {
  const { t, lang } = useLang()
  const widths = withDay ? DAY_W : MONTH_W
  const [text, setText] = useState(() => fromISO(value, lang, withDay))
  const [open, setOpen] = useState(false)
  const boxRef = useRef(null)
  const btnRef = useRef(null)

  const res = parseText(text, widths)

  // ค่าถูกตั้งจากข้างนอก (เช่นเติม "วันเริ่มนับวันจริง" ให้ตามวันเริ่มนับเครดิต) หรือสลับภาษา
  // → เขียนข้อความในช่องใหม่ · ค่าว่างจากข้างนอกไม่ล้างสิ่งที่พิมพ์ค้างไว้
  //   (วันที่ที่ยังไม่ครบหรือไม่มีจริงก็ส่งค่าว่างออกไปเหมือนกัน)
  const [seen, setSeen] = useState({ value, lang })
  if (seen.value !== value || seen.lang !== lang) {
    setSeen({ value, lang })
    if (seen.lang !== lang) {
      if (res.iso) setText(fromISO(res.iso, lang, withDay))
    } else if (value && value !== res.iso) {
      setText(fromISO(value, lang, withDay))
    }
  }

  const commit = (next) => {
    setText(next)
    onChange(parseText(next, widths).iso ?? '')
  }

  const onInput = (e) => {
    const deleting = String(e.nativeEvent?.inputType ?? '').startsWith('delete')
    let digits = toDigits(e.target.value, widths)
    // กด backspace ทับ "/" ที่แอปใส่ให้: ตัวเลขไม่ลดลง ถ้าใส่ "/" กลับไปเฉย ๆ จะเหมือนปุ่มลบไม่ทำงาน
    // → ลบตัวเลขตัวท้ายไปด้วย 1 ตัว (กดลบครั้งเดียวต้องเห็นผล)
    if (deleting && digits === toDigits(text, widths)) digits = digits.slice(0, -1)
    commit(mask(digits, widths, !deleting))
  }

  const pick = (iso) => {
    setOpen(false)
    commit(fromISO(iso, lang, withDay))
    btnRef.current?.focus()
  }

  // ปิดปฏิทินด้วย Esc หรือแตะ/คลิกนอกกล่อง
  // Esc: preventDefault + stopPropagation กันไม่ให้ <dialog> ของฟอร์มปิดไปด้วย (กดอีกครั้งจึงปิดฟอร์ม)
  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (!boxRef.current?.contains(e.target)) setOpen(false)
    }
    const onKey = (e) => {
      if (e.key !== 'Escape') return
      e.preventDefault()
      e.stopPropagation()
      setOpen(false)
      btnRef.current?.focus()
    }
    document.addEventListener('pointerdown', onDown)
    document.addEventListener('keydown', onKey, true)
    return () => {
      document.removeEventListener('pointerdown', onDown)
      document.removeEventListener('keydown', onKey, true)
    }
  }, [open])

  // บรรทัดใต้ช่อง: วันที่ที่ระบบเข้าใจเป็นคำเต็ม ("ศุกร์ 9 ตุลาคม 2569") หรือข้อความเตือน
  let note = hint ?? ''
  if (res.err) {
    note = res.bad
      ? t('eBadDate', { m: monthNames(lang)[res.bad.m - 1], y: yearLabel(lang, res.bad.y), n: res.bad.max })
      : t(res.err)
  } else if (res.iso) {
    const tail = `${monthNames(lang)[res.m - 1]} ${yearLabel(lang, res.y)}`
    note = withDay ? `${weekdayName(lang, res.iso)} ${res.d} ${tail}` : tail
  }

  return (
    <div className={'field dfield' + (withDay ? ' has-day' : '')}>
      <label htmlFor={id}>{label}</label>
      <div className="dbox" ref={boxRef}>
        <input
          id={id}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          placeholder={t(withDay ? 'dPlace' : 'mPlace')}
          value={text}
          onChange={onInput}
          aria-describedby={`${id}-n`}
          aria-invalid={res.err ? 'true' : undefined}
        />
        <button
          ref={btnRef}
          type="button"
          className="dcal"
          aria-label={t(withDay ? 'dOpenCal' : 'dOpenMonth')}
          aria-expanded={open}
          onClick={() => setOpen((o) => !o)}
        >
          <CalIcon />
        </button>
        {open && <Calendar iso={res.iso ?? ''} withDay={withDay} onPick={pick} />}
      </div>
      <span id={`${id}-n`} className={'dnote' + (res.err ? ' bad' : '')} role={res.err ? 'alert' : undefined}>
        {note}
      </span>
    </div>
  )
}

// วันที่เต็ม — value/onChange เป็น 'YYYY-MM-DD' (ค.ศ.) หรือ '' ถ้ายังไม่ครบหรือไม่มีจริง
export default function DateField(props) {
  return <Field {...props} withDay />
}

// เดือน (บัญชีเดือน) — value/onChange เป็น 'YYYY-MM' (ค.ศ.) หรือ ''
export function MonthField(props) {
  return <Field {...props} withDay={false} />
}
