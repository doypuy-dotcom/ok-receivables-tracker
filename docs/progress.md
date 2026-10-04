# progress.md — บันทึกความคืบหน้า

## M0 — scaffold + deploy-ready ✅ (2026-10-04)

### ทำอะไรไปแล้ว

**Scaffold**

- สร้างโปรเจกต์ Vite + React (JavaScript) ในโฟลเดอร์ปัจจุบัน โดยเก็บไฟล์เดิมไว้ครบ
  (`README.md`, `.gitignore`, `CLAUDE.md`, `docs/`)
- ไฟล์ที่เพิ่ม: `package.json`, `vite.config.js`, `.oxlintrc.json`, `index.html`,
  `public/`, `src/main.jsx`, `src/App.jsx`, `src/index.css`, `src/lib/supabase.js`,
  `.env.example`
- ติดตั้ง `@supabase/supabase-js`, `react`, `react-dom` + dev deps (vite, plugin-react, oxlint)

**หน้าเดียว (`src/App.jsx`)**

- Header: โลโก้ "OK" + ชื่อบริษัท ตามโทนสี/ฟอนต์ของ `docs/ui-reference.html`
  (ฟอนต์ Anuphan, `--primary #1C5DA3`, รองรับ dark mode)
- ชื่อหน้า: "ระบบติดตามยอดค้างชำระ"
- การ์ด "สถานะการเชื่อมต่อ": แสดงว่าเชื่อมต่อ Supabase ได้หรือไม่
- ยังไม่มี demo data จาก ui-reference ในแอป (ตามกฎใน CLAUDE.md)

**Supabase (`src/lib/supabase.js`)**

- อ่านค่าจาก `import.meta.env.VITE_SUPABASE_URL` และ `VITE_SUPABASE_PUBLISHABLE_KEY`
- export `supabase` client, `isConfigured`, และ `checkSupabaseHealth()`
- `checkSupabaseHealth()` เรียก Auth health endpoint: `GET {url}/auth/v1/health`
  พร้อม header `apikey` คืนค่า `{ ok, detail }`
- ไม่มี service_role key / secret / admin token ในโค้ดฝั่ง browser

**Environment / ความปลอดภัย**

- `.env.example` มีแค่ชื่อตัวแปร ไม่มีค่าจริง
- ตรวจแล้วว่า `.env.local` ถูก ignore (`.gitignore:70` `.env.*`) และ
  `.env.example` ไม่ถูก ignore (`.gitignore:71` `!.env.example`)

### ตรวจแล้วว่าผ่าน

- `npm install` — 33 packages, 0 vulnerabilities
- `npm run build` — ผ่าน (dist/index.html 0.81 kB, css 2.62 kB, js 230.45 kB)
- `npm run lint` — ไม่มี error
- `git check-ignore .env.local` — ถูก ignore

### ยังไม่ทำในขั้นนี้ (ตามที่สั่ง)

- login / auth, role เจ้าของ–ฝ่ายขาย
- database tables (customers, receivables, payments, audit_logs)
- PWA (manifest, service worker)
- i18n ไทย/อังกฤษ, export JPG/PDF, หน้าตารางยอดค้างชำระจริง

### คำสั่งที่ใช้รันในเครื่อง

```bash
cp .env.example .env.local   # แล้วใส่ค่า URL + publishable key
npm install
npm run dev
```
- Live URL: https://ok-receivables.vercel.app (deployed on Vercel, tested on iPhone via 5G)
