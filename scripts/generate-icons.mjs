// สร้างไอคอน PWA (PNG) จากไฟล์ต้นฉบับ public/logo-ok.svg — รัน: npm run icons
// ทำในเครื่อง ไม่ใช่ตอน build และ "ห้ามใช้รูปจากอินเทอร์เน็ต" ไอคอนทุกไฟล์มาจาก SVG ในรีโปนี้เท่านั้น
// รันซ้ำได้ ผลลัพธ์เหมือนเดิมทุกครั้ง (ตัวอักษรเป็นเส้น ไม่ต้องใช้ฟอนต์)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Resvg } from '@resvg/resvg-js'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const SRC = join(root, 'public', 'logo-ok.svg')
const OUT = join(root, 'public', 'icons')

// ตัดคอมเมนต์ออกก่อน เพราะคอมเมนต์ในไฟล์ต้นฉบับก็พูดถึงแท็บเหล่านี้
const src = readFileSync(SRC, 'utf8').replace(/<!--[\s\S]*?-->/g, '')

const bg = src.match(/<rect[^>]*id="bg"[^>]*fill="(#[0-9a-fA-F]{3,8})"/)?.[1]
const mark = src.match(/<g id="mark"([\s\S]*?)<\/g>/)?.[1]
if (!bg || !mark) {
  console.error(`อ่าน ${SRC} ไม่ได้: ต้องมี <rect id="bg" ... fill="#..."> และ <g id="mark"> … </g>`)
  process.exit(1)
}

// radius 121/512 = มุมโค้งเท่ากับโลโก้ในแอป (.logo ของ src/index.css)
// scale ย่อตัวอักษรเข้าหากึ่งกลาง: maskable ต้องอยู่ในวงกลมกลางภาพ 80% (Android ครอบเป็นวงกลม/สี่เหลี่ยมมน)
const ICONS = [
  { file: 'icon-192.png', size: 192, radius: 121, scale: 1, note: 'Android/Chrome ทั่วไป' },
  { file: 'icon-512.png', size: 512, radius: 121, scale: 1, note: 'หน้า splash + ร้านแอป' },
  { file: 'icon-512-maskable.png', size: 512, radius: 0, scale: 0.85, note: 'Android maskable' },
  { file: 'apple-touch-icon-180.png', size: 180, radius: 0, scale: 0.88, note: 'iPhone (iOS มนมุมให้เอง)' },
]

const variant = ({ size, radius, scale }) => `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="${radius}" fill="${bg}"/>
  <g transform="translate(256 256) scale(${scale}) translate(-256 -256)"><g${mark}</g></g>
</svg>`

mkdirSync(OUT, { recursive: true })
for (const icon of ICONS) {
  const png = new Resvg(variant(icon), { fitTo: { mode: 'width', value: icon.size } }).render().asPng()
  writeFileSync(join(OUT, icon.file), png)
  console.log(`${icon.file.padEnd(26)} ${String(icon.size).padStart(3)}px  ${icon.note}`)
}
