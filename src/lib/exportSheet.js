// ส่งออกหน้าสรุปรายเดือนเป็น JPG / PDF (V2)
//
// วิธี: **ถ่ายรูป DOM แผ่นเดียวกับที่เห็นบนจอ** (`.sheet` ใน ReportSheet.jsx) ไม่มี layout ที่สอง
// สำหรับไฟล์ (AGENTS.md) → สิ่งที่ลูกค้าเห็นบนจอกับสิ่งที่พิมพ์ออกมาเป็นของเดียวกันเสมอ
//   html-to-image → canvas → JPG  ·  jsPDF ใส่รูปนั้นลง A4 แนวตั้ง → PDF
//   (architecture.md ข้อ 2: แปลงเป็นรูปก่อนทำให้ภาษาไทยใน PDF ไม่เพี้ยน — jsPDF ไม่มีฟอนต์ไทยในตัว)
//
// A4 แนวตั้งที่ 96dpi = 794 × 1123 px (ขนาดจริงของ .sheet) · ถ่ายที่ pixelRatio 2 ≈ 192dpi พิมพ์คมพอ
// บนมือถือ .sheet ถูกย่อด้วย transform: scale() ที่กล่องนอก **ไม่ใช่ที่ตัว .sheet**
// จึงถ่ายได้ขนาดจริง 794px เท่ากันทุกเครื่อง (transform ของ element แม่ไม่มีผลกับ offsetWidth ของลูก)
//
// ภาษาไทยไม่เพี้ยน: รอ `document.fonts.ready` แล้วฝัง @font-face (Anuphan) เป็น data: URI ลงในรูป
// ไม่มีสัญญาณเน็ต → ฟอนต์โหลดไม่ได้ (ไม่ได้ cache ไว้ตาม architecture.md ข้อ 8) → ไม่ปล่อยไฟล์ แจ้ง error
//
// iPhone / iPad โดยเฉพาะตอนเปิดจากไอคอน PWA ดาวน์โหลดไฟล์ไม่สะดวก (ลิงก์ดาวน์โหลดมักเปิดทิ้งไว้เฉย ๆ)
// → ใช้ `navigator.share({ files })` ก่อนเมื่อ `canShare` บอกว่าได้ ผู้ใช้จะบันทึกลงไฟล์ / พิมพ์ /
//   ส่งเข้า LINE ได้จากแผ่นแชร์ของระบบ · แชร์ไม่ได้หรือเบราว์เซอร์ปฏิเสธ → ค่อยใช้ลิงก์ดาวน์โหลดแบบเดิม
// **เฉพาะมือถือและแท็บเล็ตเท่านั้น** (iOS / iPadOS / Android) — บนคอมให้ดาวน์โหลดตรงเสมอ
// เหตุผล (ลูกค้าแจ้งหลังทดสอบ 19 ต.ค.): Chrome บน Windows ก็มี navigator.share แต่ไปเปิดหน้าต่าง
// Share ของ Windows ซึ่งเสียเวลาเปล่า คนใช้คอมคาดหวังไฟล์ลงโฟลเดอร์ Downloads ตรง ๆ

// ขนาดกระดาษ — ต้องตรงกับ .sheet ใน src/index.css และค่าคงที่ใน ReportSheet.jsx
export const SHEET_W = 794
export const SHEET_H = 1123
const A4_MM = { w: 210, h: 297 }
const JPEG_QUALITY = 0.95

function exportError(key) {
  const err = new Error(key)
  err.key = key
  return err
}

// ถ่ายทุกหน้าเป็น canvas ขนาดจริง
async function captureAll(nodes) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) throw exportError('eExportOffline')

  const { toCanvas, getFontEmbedCSS } = await import('html-to-image')

  // ฟอนต์ต้องพร้อมก่อนถ่าย ไม่งั้นรูปจะได้ฟอนต์สำรองของเครื่อง
  if (typeof document !== 'undefined' && document.fonts?.ready) {
    try {
      await document.fonts.ready
    } catch {
      // เบราว์เซอร์ไม่รองรับ → ไปต่อ แล้วค่อยฝังฟอนต์ด้านล่าง
    }
  }

  // ฝังฟอนต์ครั้งเดียวแล้วใช้ซ้ำทุกหน้า (ถ้าปล่อยให้ถ่ายแต่ละหน้าไปดึงฟอนต์เอง จะช้าหลายเท่า)
  let fontEmbedCSS
  try {
    fontEmbedCSS = await getFontEmbedCSS(nodes[0])
  } catch {
    throw exportError('eExportFont')
  }

  const opts = {
    width: SHEET_W,
    height: SHEET_H,
    pixelRatio: 2,
    backgroundColor: '#ffffff',
    fontEmbedCSS,
  }

  const canvases = []
  for (let i = 0; i < nodes.length; i += 1) {
    // รอบอุ่นเครื่อง 1 ครั้ง: บน iOS Safari รูปแรกมักออกมาก่อนฟอนต์/รูปในหน้าเข้าที่
    // (ข้อจำกัดที่รู้กันของ html-to-image) ทิ้งผลรอบแรกแล้วถ่ายใหม่
    if (i === 0) await toCanvas(nodes[0], opts)
    canvases.push(await toCanvas(nodes[i], opts))
  }
  return canvases
}

function canvasToBlob(canvas) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(exportError('eExport'))),
      'image/jpeg',
      JPEG_QUALITY,
    )
  })
}

function downloadFile(file) {
  const url = URL.createObjectURL(file)
  const a = document.createElement('a')
  a.href = url
  a.download = file.name
  a.rel = 'noopener'
  document.body.appendChild(a)
  a.click()
  a.remove()
  // ปล่อย URL ช้า ๆ: บางเบราว์เซอร์ยังอ่านไฟล์อยู่ตอนกดบันทึก
  setTimeout(() => URL.revokeObjectURL(url), 10000)
}

// เครื่องนี้เป็นมือถือหรือแท็บเล็ตไหม (ตัวเดียวที่ควรใช้แผ่นแชร์ของระบบ)
function isHandheld() {
  if (typeof navigator === 'undefined') return false

  // Chrome / Edge / Android: ถามเบราว์เซอร์ตรง ๆ แม่นกว่าการเดาจาก userAgent
  const uaData = navigator.userAgentData
  if (typeof uaData?.mobile === 'boolean') {
    if (uaData.mobile) return true
    const platform = uaData.platform ?? ''
    if (/android/i.test(platform)) return true // แท็บเล็ต Android บอก mobile = false
    if (/windows|macos|linux|chrome os|chromeos/i.test(platform)) return false
  }

  // Safari / เบราว์เซอร์ที่ยังไม่มี userAgentData
  const ua = navigator.userAgent ?? ''
  if (/iPhone|iPod|Android/i.test(ua)) return true
  // iPadOS 13 ขึ้นไปรายงานตัวเองว่าเป็น Macintosh — แยกจาก Mac จริงด้วยจำนวนจุดสัมผัส
  // (Mac ไม่มีจอสัมผัส maxTouchPoints = 0 เสมอ)
  return /iPad/.test(ua) || (/Macintosh/.test(ua) && (navigator.maxTouchPoints ?? 0) > 1)
}

// คืน 'shared' | 'saved' | 'cancelled'
async function deliver(files, title) {
  const canShare = isHandheld() && navigator.canShare && navigator.share
  if (canShare) {
    let shareable = false
    try {
      shareable = navigator.canShare({ files })
    } catch {
      shareable = false
    }
    if (shareable) {
      try {
        await navigator.share({ files, title })
        return 'shared'
      } catch (err) {
        // ผู้ใช้ปิดแผ่นแชร์เอง = ไม่ใช่ความผิดพลาด ไม่ต้องดาวน์โหลดซ้ำ
        if (err?.name === 'AbortError') return 'cancelled'
        // เบราว์เซอร์ปฏิเสธ (เช่นห่างจากการกดปุ่มนานเกินไป) → ใช้ลิงก์ดาวน์โหลดแทน
      }
    }
  }
  for (const file of files) downloadFile(file)
  return 'saved'
}

/**
 * ส่งออกกระดาษทุกแผ่นที่เห็นบนจอ
 * @param kind 'pdf' | 'jpg'
 * @param nodes element ของ .sheet ทุกแผ่น (เรียงตามหน้า)
 * @param baseName ชื่อไฟล์ไม่รวมนามสกุล เช่น 'OK-monthly-2569-10'
 * @param title ชื่อที่โชว์บนแผ่นแชร์ของระบบ
 * @returns 'shared' | 'saved' | 'cancelled'
 * @throws Error ที่มี .key เป็นคีย์ข้อความของ i18n
 */
export async function exportSheets({ kind, nodes, baseName, title }) {
  if (!nodes?.length) throw exportError('eExport')

  const canvases = await captureAll(nodes)

  if (kind === 'jpg') {
    const files = []
    for (let i = 0; i < canvases.length; i += 1) {
      const blob = await canvasToBlob(canvases[i])
      // หลายหน้า → ใส่เลขหน้าท้ายชื่อไฟล์ หน้าเดียวไม่ต้องมี
      const name = canvases.length > 1 ? `${baseName}-p${i + 1}.jpg` : `${baseName}.jpg`
      files.push(new File([blob], name, { type: 'image/jpeg' }))
    }
    return deliver(files, title)
  }

  const { jsPDF } = await import('jspdf')
  const doc = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4', compress: true })
  canvases.forEach((canvas, i) => {
    if (i > 0) doc.addPage()
    doc.addImage(canvas.toDataURL('image/jpeg', JPEG_QUALITY), 'JPEG', 0, 0, A4_MM.w, A4_MM.h)
  })
  const file = new File([doc.output('blob')], `${baseName}.pdf`, { type: 'application/pdf' })
  return deliver([file], title)
}
