// กระดาษ A4 แนวตั้งของหน้าสรุปรายเดือน (V2)
//
// **DOM ก้อนนี้คือสิ่งที่ถูกถ่ายเป็นไฟล์ JPG / PDF** ไม่มี layout ที่สองสำหรับไฟล์ (AGENTS.md)
// ขนาดคงที่ 794 × 1123 px = A4 แนวตั้งที่ 96dpi ทั้งบนจอและในไฟล์
//
// บนมือถือ: ย่อให้พอดีความกว้างจอด้วย transform: scale() ที่ **กล่องนอก** (.sheet-stack)
// ไม่ใช่ที่ตัว .sheet → ไม่ต้องเลื่อนแนวนอน แต่ตอนส่งออกยังถ่ายจากขนาดจริง 794px
// (ลูกค้าสั่ง 19 ต.ค. ข้อ 2) · ความสูงของกล่องนอกคูณด้วย scale เอง ไม่ให้เหลือที่ว่างใต้กระดาษ
//
// การแบ่งหน้าคำนวณจากค่าคงที่ด้านล่าง ซึ่ง **ต้องตรงกับ .sheet / .rep ใน src/index.css**
// (ทุกแถวสูงเท่ากันและไม่ตัดบรรทัด จึงคำนวณได้ตรงโดยไม่ต้องวัดจาก DOM)
// หน้าแรกได้ 28 แถว — กระดาษเดิมของลูกค้าใส่ 25 บริษัทในแผ่นเดียว (ลูกค้าสั่ง 19 ต.ค. ข้อ 1)
//
// ชื่อบริษัทและหัวคอลัมน์ต้องแสดงเต็ม ห้ามตัดหาย (ลูกค้าสั่งเพิ่มหลังทดสอบ 19 ต.ค.):
// หัวคอลัมน์ขึ้นได้ 2–3 บรรทัด ส่วนเซลล์ชื่อบริษัทย่อขนาดตัวอักษรลงจนพอดี
// ถ้าย่อถึง 10px แล้วบรรทัดเดียวยังไม่พอ ก็แสดง 2 บรรทัดเล็ก ๆ **ในแถวสูง 30px เดิม** (lib/fitText.js)
// ทุกทางเลือกรักษาความสูงแถว 30px ไว้เท่ากัน การแบ่งหน้าจึงไม่เปลี่ยนตามความยาวของชื่อ
import { useEffect, useRef, useState } from 'react'
import { fitFontPx, fitHeaderPx, fitNameCell, textFits } from '../lib/fitText.js'
import { fmtDateNum, fmtMonth, fmtMonthNum, money, stampParts } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import { SHEET_H, SHEET_W } from '../lib/exportSheet.js'

const PAGE_PAD = 45 // 12mm
const CONTENT_H = SHEET_H - PAGE_PAD * 2
const H_HEAD = 64 // หัวรายงาน (เดือน + ดู ณ) มีแต่หน้าแรก
const H_THEAD = 48 // หัวตาราง — สูงพอให้หัวคอลัมน์ขึ้นได้ถึง 3 บรรทัด (อังกฤษยาวกว่าไทย)
const H_ROW = 30
const H_TOTAL = 34
const H_CARRY_HEAD = 38
const H_CARRY_LINE = 22
const H_FOOT = 20 // บรรทัดเลขหน้าท้ายกระดาษ
const SCREEN_GAP = 16 // ช่องว่างระหว่างแผ่นบนจอ (ไม่มีผลกับไฟล์ที่ได้)
// เผื่อไว้ 24px: เส้นตารางและการปัดเศษความสูงบรรทัดของแต่ละเบราว์เซอร์คลาดกันได้เล็กน้อย
// เนื้อหาล้นออกนอกกระดาษแล้วถูกตัด (overflow: hidden) แย่กว่าการได้แถวน้อยลง 1 แถว
const SAFE_H = 24
const USABLE_H = CONTENT_H - H_FOOT - SAFE_H

// หน้าแรก 28 แถว หน้าถัดไป 30 แถว — มากกว่ากระดาษเดิมของลูกค้าที่ใส่ 25 บริษัทต่อแผ่น
const ROWS_FIRST = Math.floor((USABLE_H - H_HEAD - H_THEAD - H_TOTAL) / H_ROW)
const ROWS_NEXT = Math.floor((USABLE_H - H_THEAD - H_TOTAL) / H_ROW)
const CARRY_PER_PAGE = Math.floor((USABLE_H - H_CARRY_HEAD) / H_CARRY_LINE)

// ความกว้างคอลัมน์ รวม 704px = ความกว้างของ .rep ใน index.css
// ชื่อบริษัทได้ช่องกว้างที่สุด ที่เหลือกว้างพอดีเนื้อหาจริง:
// เงิน 12 ตัวอักษร (9,999,999.99) · วันที่ 10 ตัวอักษร (31/12/2569) · บัญชีเดือน 5 ตัวอักษร (10/69)
const PAD_X = 6 // padding ซ้าย-ขวาของเซลล์ ต้องตรงกับ .rep th / .rep td
const COLS = [
  { k: 'cSeq', w: 42, num: true },
  { k: 'cCompany', w: 242, num: false },
  { k: 'cCredit', w: 54, num: true },
  { k: 'cAcct', w: 62, num: true },
  { k: 'cAmount', w: 102, num: true },
  { k: 'cBalance', w: 102, num: true },
  { k: 'cPaidDate', w: 100, num: true },
]
const CARRY_W = 704
const BODY_PX = 13.5 // = font-size ของ .sheet
const HEAD_PX = 13 // = font-size ของ .rep thead th
const CARRY_PX = 13 // = font-size ของ .rep-carry p
// ชื่อบริษัทที่ยาวจนบรรทัดเดียวไม่พอแม้ย่อถึง 10px จะแสดง 2 บรรทัดที่ขนาดนี้
// 2 บรรทัด × line-height 13px = 26px ยังอยู่ในแถวสูง 30px เดิม (ต้องตรงกับ .c-name .two ใน index.css)
const NAME2_PX = 11

// แบ่งแถวลงกระดาษแต่ละแผ่น แล้ววางบล็อก "ยอดค้างข้ามเดือน" ต่อท้ายหน้าสุดท้ายถ้าที่เหลือพอ
// ไม่พอก็ขึ้นหน้าใหม่ทั้งบล็อก (อ่านง่ายกว่าแบ่งครึ่งบล็อก)
function paginate(rows, carry) {
  const pages = []
  let i = 0
  do {
    const cap = pages.length === 0 ? ROWS_FIRST : ROWS_NEXT
    pages.push({ table: true, rows: rows.slice(i, i + cap), carry: [] })
    i += cap
  } while (i < rows.length)

  if (carry.length > 0) {
    const last = pages[pages.length - 1]
    const used = (pages.length === 1 ? H_HEAD : 0) + H_THEAD + last.rows.length * H_ROW + H_TOTAL
    const free = USABLE_H - used
    const fit = Math.floor((free - H_CARRY_HEAD) / H_CARRY_LINE)
    if (fit >= carry.length) {
      last.carry = carry
    } else {
      let rest = carry
      while (rest.length > 0) {
        pages.push({ table: false, rows: [], carry: rest.slice(0, CARRY_PER_PAGE) })
        rest = rest.slice(CARRY_PER_PAGE)
      }
    }
  }
  return pages
}

export default function ReportSheet({ month, rows, total, carry, asOf, userName }) {
  const { t, lang } = useLang()
  const boxRef = useRef(null)
  const [scale, setScale] = useState(1)
  // ฟอนต์ไทยมาจาก Google Fonts: ก่อนโหลดเสร็จ measureText จะได้ความกว้างของฟอนต์สำรอง
  // ค่านี้ส่งต่อเป็น "รุ่นของการวัด" ให้ fitText → วัดใหม่ทั้งแผ่นเมื่อฟอนต์จริงมาถึง
  const [fontGen, setFontGen] = useState(() => (document.fonts?.status === 'loaded' ? 1 : 0))

  // ย่อให้พอดีความกว้างของพื้นที่จริง (ไม่ขยายเกิน 1 เท่า)
  useEffect(() => {
    const el = boxRef.current
    if (!el) return
    const measure = () => {
      const w = el.clientWidth
      if (w > 0) setScale(Math.min(1, w / SHEET_W))
    }
    measure()
    window.addEventListener('resize', measure)
    window.addEventListener('orientationchange', measure)
    return () => {
      window.removeEventListener('resize', measure)
      window.removeEventListener('orientationchange', measure)
    }
  }, [])

  useEffect(() => {
    let alive = true
    document.fonts?.ready?.then(() => alive && setFontGen(1))
    return () => {
      alive = false
    }
  }, [])

  // ขนาดตัวอักษรของแต่ละเซลล์ — วัดตอน render (ผลถูกแคชไว้ใน fitText ตามข้อความ + รุ่นการวัด)
  // คืน undefined เมื่อขนาดปกติก็พอ เพื่อไม่ใส่ style ที่ไม่จำเป็นลง DOM ที่จะถูกถ่ายเป็นไฟล์
  const fit = (text, ci, weight = '') => {
    const px = fitFontPx(text, COLS[ci].w - PAD_X * 2, BODY_PX, weight, fontGen)
    return px < BODY_PX ? { fontSize: px } : undefined
  }
  // ชื่อบริษัท: 1 บรรทัดขนาดปกติ → ย่อลงถึง 10px → 2 บรรทัดเล็ก ๆ ในแถวสูง 30px เดิม (lib/fitText.js)
  const fitName = (name) => fitNameCell(name, COLS[1].w - PAD_X * 2, BODY_PX, NAME2_PX, fontGen)
  const headPx = COLS.map((c) => fitHeaderPx(t(c.k), c.w - PAD_X * 2, HEAD_PX, 'bold', fontGen))
  const carryLines = carry.map((r) => {
    const text = t('repCarryLine', {
      c: r.company_name,
      m: fmtMonthNum(lang, r.account_month),
      a: money(r.balance),
    })
    const px = fitFontPx(text, CARRY_W, CARRY_PX, '', fontGen)
    // บรรทัดนี้กว้างเต็มหน้ากระดาษ (704px) จึงยาวพอเกือบทุกชื่อ แต่ถ้าไม่พอก็ต้องมี … บอก
    return { id: r.receivable_id, text, px, cut: !textFits(text, CARRY_W, px, '', fontGen) }
  })

  const pages = paginate(rows, carryLines)
  const lastTable = pages.reduce((acc, p, i) => (p.table ? i : acc), 0)
  const naturalH = pages.length * SHEET_H + (pages.length - 1) * SCREEN_GAP
  const stamp = stampParts(asOf?.viewed_at)
  const monthLabel = fmtMonth(lang, month, true)

  return (
    <div className="sheet-box" ref={boxRef} style={{ height: Math.round(naturalH * scale) }}>
      <div
        className="sheet-stack"
        style={{ width: SHEET_W, transform: `scale(${scale})`, gap: SCREEN_GAP }}
      >
        {pages.map((page, pi) => (
          <section className="sheet" key={`p${pi}`} aria-label={t('repPage', { n: pi + 1, t: pages.length })}>
            <div className="sheet-in">
              {pi === 0 && (
                <header className="rep-head">
                  <h2>{t('repHead', { m: monthLabel })}</h2>
                  <p>
                    {t('repViewedBy', {
                      d: fmtDateNum(lang, stamp.date),
                      tm: stamp.time,
                      u: userName,
                    })}
                  </p>
                </header>
              )}

              {page.table && (
                <table className="rep">
                  <colgroup>
                    {COLS.map((c) => (
                      <col key={c.k} style={{ width: c.w }} />
                    ))}
                  </colgroup>
                  <thead>
                    <tr>
                      {COLS.map((c, ci) => (
                        <th
                          key={c.k}
                          scope="col"
                          className={c.num ? 'c-num' : undefined}
                          style={headPx[ci] < HEAD_PX ? { fontSize: headPx[ci] } : undefined}
                        >
                          {t(c.k)}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {page.rows.length === 0 && (
                      <tr>
                        <td colSpan={COLS.length} className="rep-empty">
                          {t('repEmpty')}
                        </td>
                      </tr>
                    )}
                    {page.rows.map((r) => {
                      // คอลัมน์เงินและวันที่กว้างพอเสมอ แต่ใส่ fit() กันไว้ด้วย: ตัวเลขเงินที่ถูกตัดครึ่ง
                      // บนกระดาษอันตรายกว่าตัวเลขที่เล็กลงเล็กน้อย
                      const amount = money(r.total_amount)
                      const balance = money(r.balance)
                      const paid = fmtDateNum(lang, r.actual_due_date)
                      const name = fitName(r.company_name)
                      return (
                        <tr key={r.receivable_id}>
                          <td className="c-num">{r.seq}</td>
                          {/* ความสูงแถวคงที่ 30px ทุกกรณี การแบ่งหน้าจึงไม่ขึ้นกับความยาวของชื่อ */}
                          <td className="c-name">
                            {name.lines.length > 1 ? (
                              <span className="two" style={{ fontSize: name.px }}>
                                {name.lines.map((ln, li) => (
                                  <span key={li} className={ln.cut ? 'cut' : undefined}>
                                    {ln.text}
                                  </span>
                                ))}
                              </span>
                            ) : name.px < BODY_PX ? (
                              <span style={{ fontSize: name.px }}>{name.lines[0].text}</span>
                            ) : (
                              name.lines[0].text
                            )}
                          </td>
                          <td className="c-num">{r.credit_days}</td>
                          <td className="c-num">{fmtMonthNum(lang, r.account_month)}</td>
                          <td className="c-num" style={fit(amount, 4)}>
                            {amount}
                          </td>
                          <td className="c-num" style={fit(balance, 5)}>
                            {balance}
                          </td>
                          <td className="c-num" style={fit(paid, 6)}>
                            {paid}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                  {/* แถวยอดรวมอยู่หน้าสุดท้ายของตาราง · ตัวเลขมาจาก view monthly_report_total เท่านั้น
                      เดือนที่ไม่มีการ์ดเลยจะไม่มีแถวใน view → ไม่แสดงแถวนี้ (ไม่เขียนเลข 0 ขึ้นมาเอง) */}
                  {pi === lastTable && total && (
                    <tfoot>
                      <tr>
                        <td colSpan={4}>{t('repTotal')}</td>
                        <td className="c-num" style={fit(money(total.total_amount_sum), 4, 'bold')}>
                          {money(total.total_amount_sum)}
                        </td>
                        <td className="c-num" style={fit(money(total.balance_sum), 5, 'bold')}>
                          {money(total.balance_sum)}
                        </td>
                        <td />
                      </tr>
                    </tfoot>
                  )}
                </table>
              )}

              {page.carry.length > 0 && (
                <div className="rep-carry">
                  <h3>{t('repCarryH', { d: fmtDateNum(lang, asOf?.today) })}</h3>
                  {page.carry.map((line) => (
                    <p
                      key={line.id}
                      className={line.cut ? 'cut' : undefined}
                      style={line.px < CARRY_PX ? { fontSize: line.px } : undefined}
                    >
                      {line.text}
                    </p>
                  ))}
                </div>
              )}

              <footer className="sheet-foot">
                {pi > 0 && <span>{t('repHead', { m: monthLabel })} · </span>}
                <span>{t('repPage', { n: pi + 1, t: pages.length })}</span>
              </footer>
            </div>
          </section>
        ))}
      </div>
    </div>
  )
}
