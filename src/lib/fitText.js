// ย่อขนาดตัวอักษรเฉพาะเซลล์ให้ข้อความพอดีช่อง (ลูกค้าสั่งหลังทดสอบ 19 ต.ค.)
//
// รายงานนี้เอาไว้พิมพ์ เจ้าของต้องอ่านชื่อบริษัทได้ครบ จึง **ห้ามตัดชื่อหายเฉย ๆ**
// แต่ถ้าปล่อยให้เซลล์สูงตามเนื้อหา ความสูงแถวจะไม่เท่ากัน การแบ่งหน้าที่คำนวณจากค่าคงที่
// ใน ReportSheet.jsx จะเพี้ยนทันที → ลำดับการลดขนาดจึงเป็น (ความสูงแถว 30px คงที่ทุกกรณี):
//   1. บรรทัดเดียวขนาดปกติ 13.5px
//   2. บรรทัดเดียว ย่อลงจนพอดี ต่ำสุด 10px
//   3. ยังไม่พอ → แบ่งเป็น 2 บรรทัดเล็ก (11px ย่อได้ถึง 10px) ยังอยู่ในแถวสูง 30px เดิม
//   4. ยาวจนสองบรรทัดที่ 10px ก็ไม่พอ (ประมาณ 115 ตัวอักษรไทยขึ้นไป) → ใส่ … ให้คนอ่านรู้ว่ายังมีต่อ
//      (เป็นกรณีสุดท้ายจริง ๆ ไม่ใช่การตัดแบบไม่มีอะไรบอก)
//
// การแบ่ง 2 บรรทัดทำเองในโค้ด ไม่พึ่ง line-break ของเบราว์เซอร์ เพราะภาษาไทยไม่มีช่องว่างระหว่างคำ
// เบราว์เซอร์แต่ละตัวตัดคำไทยไม่เหมือนกัน (บางตัวไม่ตัดเลย) ผลที่ได้ต้องเหมือนกันทั้งบนจอและในไฟล์
//
// วัดความกว้างด้วย canvas measureText ไม่ใช่วัดจาก DOM เพราะ
// 1) ไม่ทำให้เบราว์เซอร์ต้อง reflow ทีละแถว (30 แถวต่อแผ่น)
// 2) ได้ค่าเท่ากันทั้งตอนแสดงบนจอและตอน html-to-image ถ่ายเป็นไฟล์
// ความกว้างของข้อความเป็นสัดส่วนตรงกับขนาดตัวอักษรเมื่อเป็นฟอนต์เดียวกัน จึงวัดที่ขนาดปกติครั้งเดียว
// แล้วเทียบบัญญัติไตรยางศ์หาขนาดที่พอดีได้

// ต้องตรงกับ font-family ของ body ใน src/index.css
const STACK = "'Anuphan', 'Noto Sans Thai', 'Leelawadee UI', 'Tahoma', system-ui, sans-serif"
export const MIN_PX = 10 // เล็กที่สุดที่ลูกค้ายอมรับ (ยังอ่านออกบนกระดาษ)
const SAFE_W = 1 // เผื่อ 1px กันการปัดเศษของเบราว์เซอร์

// สระ/วรรณยุกต์ที่เกาะพยัญชนะตัวหน้า (ห้ามขึ้นบรรทัดใหม่แยกจากตัวที่มันเกาะ)
const MARK = /[ัำิ-ฺ็-๎]/
// สระหน้า เ แ โ ใ ไ — เขียนก่อนแต่ออกเสียงหลัง ต้องอยู่บรรทัดเดียวกับพยัญชนะตัวถัดไป
const LEAD = /[เ-ไ]/

let ctx
const cache = new Map()

function textWidth(text, px, weight, gen) {
  // gen อยู่ในกุญแจของแคชด้วย: ค่าที่วัดก่อนฟอนต์ไทยโหลดเสร็จเป็นความกว้างของฟอนต์สำรอง
  // ซึ่งไม่ใช่ของจริง ต้องไม่ถูกนำกลับมาใช้หลังฟอนต์โหลดเสร็จ
  const key = gen + '|' + weight + '|' + px + '|' + text
  const hit = cache.get(key)
  if (hit !== undefined) return hit
  if (ctx === undefined) {
    ctx = document.createElement('canvas').getContext('2d') ?? null
  }
  if (!ctx) return 0 // ไม่มี canvas → ใช้ขนาดปกติไปเลย ดีกว่าเดาแล้วย่อผิด
  ctx.font = (weight ? weight + ' ' : '') + px + 'px ' + STACK
  const w = ctx.measureText(text).width
  cache.set(key, w)
  return w
}

// ข้อความบรรทัดนี้พอดีช่องที่ขนาดนี้ไหม (0 = วัดไม่ได้ ให้ถือว่าพอดี)
export function textFits(text, maxW, px, weight = '', gen = 0) {
  const w = textWidth(text, px, weight, gen)
  return w === 0 || w <= maxW
}

// ข้อความบรรทัดเดียว (ชื่อบริษัท, ตัวเลขเงิน, บรรทัดยอดค้าง): ย่อให้ทั้งเส้นพอดีความกว้างช่อง
export function fitFontPx(text, maxW, basePx, weight = '', gen = 0) {
  if (!text) return basePx
  const w = textWidth(text, basePx, weight, gen)
  if (w === 0 || w <= maxW) return basePx
  const px = Math.floor(((basePx * (maxW - SAFE_W)) / w) * 2) / 2 // ปัดลงทีละ 0.5px
  return Math.max(MIN_PX, Math.min(basePx, px))
}

// หัวคอลัมน์: ขึ้นบรรทัดใหม่ได้ (CSS) จึงวัดแค่ "คำที่ยาวที่สุด" ว่าพอดีความกว้างช่องไหม
// คำไทยอย่าง "วันที่รับเงินจริง" ไม่มีช่องว่างให้ตัดบรรทัด ถ้ากว้างเกินก็จะถูกย่อลงจนแสดงได้เต็มคำ
export function fitHeaderPx(text, maxW, basePx, weight = '', gen = 0) {
  if (!text) return basePx
  let px = basePx
  for (const word of String(text).split(/\s+/)) {
    px = Math.min(px, fitFontPx(word, maxW, basePx, weight, gen))
  }
  return px
}

// แบ่งข้อความเป็นกลุ่มที่ห้ามแยกจากกัน (พยัญชนะ + สระ/วรรณยุกต์ที่เกาะอยู่ และสระหน้า + ตัวถัดไป)
function clusters(text) {
  const ch = Array.from(text)
  const out = []
  let i = 0
  while (i < ch.length) {
    let s = ch[i++]
    while (i < ch.length && LEAD.test(s.slice(-1))) s += ch[i++]
    while (i < ch.length && MARK.test(ch[i])) s += ch[i++]
    out.push(s)
  }
  return out
}

// หาจุดตัด 2 บรรทัดที่ทำให้บรรทัดที่กว้างที่สุดแคบที่สุด
// ตัดที่ช่องว่างก่อน (อ่านง่ายกว่า) ถ้าไม่มีช่องว่างเลย — ชื่อไทยส่วนใหญ่เป็นแบบนั้น — ค่อยตัดกลางคำ
function splitTwoLines(text, basePx, weight, gen) {
  const cl = clusters(text)
  if (cl.length < 2) return [text, '']
  const w = cl.map((c) => textWidth(c, basePx, weight, gen))
  const total = w.reduce((a, b) => a + b, 0)
  const spaceCuts = []
  const allCuts = []
  let run = 0
  for (let i = 0; i < cl.length - 1; i++) {
    run += w[i]
    const cut = { i: i + 1, worst: Math.max(run, total - run) }
    allCuts.push(cut)
    if (cl[i] === ' ' || cl[i + 1] === ' ') spaceCuts.push(cut)
  }
  const cuts = spaceCuts.length > 0 ? spaceCuts : allCuts
  const best = cuts.reduce((a, b) => (b.worst < a.worst ? b : a))
  return [cl.slice(0, best.i).join('').trimEnd(), cl.slice(best.i).join('').trimStart()]
}

// ชื่อบริษัทในตาราง: คืนวิธีแสดงที่ยังคงความสูงแถว 30px เสมอ
//   { px, lines: [{ text, cut }] } · cut = บรรทัดนั้นยังกว้างเกินช่อง ต้องใส่ … ให้คนอ่านรู้ว่ามีต่อ
export function fitNameCell(text, maxW, onePx, twoPx, gen = 0) {
  if (!text) return { px: onePx, lines: [{ text, cut: false }] }

  const one = fitFontPx(text, maxW, onePx, '', gen)
  if (textFits(text, maxW, one, '', gen)) return { px: one, lines: [{ text, cut: false }] }

  // บรรทัดเดียวไม่พอแม้ที่ 10px → 2 บรรทัดเล็ก ๆ ในความสูงแถวเดิม
  const parts = splitTwoLines(text, twoPx, '', gen)
  const px = Math.min(...parts.map((s) => fitFontPx(s, maxW, twoPx, '', gen)))
  return { px, lines: parts.map((s) => ({ text: s, cut: !textFits(s, maxW, px, '', gen) })) }
}
