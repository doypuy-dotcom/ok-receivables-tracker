# architecture.md — ระบบติดตามยอดค้างชำระ

> อ้างอิง: docs/prd.md, docs/schema.md · Live: https://ok-receivables.vercel.app

---

## 1. ภาพรวม

```
┌──────────────────────────────────────────────┐
│  CLIENT — PWA (Vite + React)                 │
│  iPhone Safari · Android Chrome · คอมพิวเตอร์   │
│  manifest + service worker + หน้า login        │
│  มีแค่ URL + publishable key (ไม่มี key ลับ)      │
└───────────────────┬──────────────────────────┘
                    │ HTTPS (supabase-js) + Realtime
┌───────────────────▼──────────────────────────┐
│  SUPABASE                                    │
│  Auth: อีเมล + รหัสผ่าน (ปิดการสมัครเอง)          │
│  PostgreSQL: ตารางตาม schema.md               │
│  RLS ทุกตาราง · Trigger เขียน audit_logs        │
│  View receivable_summary (ค่าคำนวณ)            │
└──────────────────────────────────────────────┘
        ▲
        │ git push main → build อัตโนมัติ
┌───────┴──────────┐
│ VERCEL (hosting) │ ← GitHub repo
└──────────────────┘
```

ไม่มีเซิร์ฟเวอร์ของเราเอง: Supabase ทำหน้าที่ database, login และบังคับสิทธิ์ (RLS) ให้ทั้งหมด เว็บจึงเป็นไฟล์ static ที่ Vercel ให้บริการ

## 2. Stack และเหตุผล

| ส่วน | เลือก | เหตุผล |
|---|---|---|
| Frontend | Vite + React (JavaScript) | เว็บ static ไม่ต้องมีเซิร์ฟเวอร์, build เร็ว, ทำ PWA ง่าย |
| Routing | react-router-dom | ปุ่มย้อนกลับบนมือถือทำงานถูก, เปิดลิงก์ตรงไปหน้ารายละเอียดได้ |
| Backend | Supabase (PostgreSQL + Auth + RLS + Realtime) | SQL ตรงกับ schema.md, มี login และระบบสิทธิ์ในตัว, ใช้ฟรีได้ |
| Hosting | Vercel | HTTPS อัตโนมัติ, deploy ทุกครั้งที่ push, ทีมเคยใช้แล้ว |
| PWA | vite-plugin-pwa | สร้าง manifest และ service worker ให้ ไม่ต้องเขียนเอง |
| ส่งออก JPG / PDF | html-to-image → JPG, jsPDF ใส่รูปนั้น → PDF | ทำในเบราว์เซอร์ ไม่ต้องมีเซิร์ฟเวอร์, แปลงเป็นรูปก่อนทำให้ภาษาไทยไม่เพี้ยนใน PDF |
| ฟอนต์ | Anuphan (Google Fonts) | อ่านภาษาไทยชัด ตรงกับ ui-reference |

## 3. การไหลของข้อมูล

**อ่าน (เปิดหน้าตาราง)**
1. แอปเรียก `receivable_summary` ผ่าน supabase-js พร้อม session ของผู้ใช้
2. RLS ตรวจว่าผู้ใช้ล็อกอินและ `is_active` → ส่งข้อมูลกลับ
3. ค่าคำนวณทั้งหมด (ยอดคงเหลือ, % แถบ, เลยกำหนด, ค้างข้ามเดือน) มาจาก view แอปแค่แสดงผล

**เขียน (ฝ่ายขายบันทึกการจ่าย)**
1. แอปตรวจข้อมูลในฟอร์ม (ช่องว่าง, ยอดเกินคงเหลือ)
2. insert ลง `payments`
3. RLS ตรวจว่า role = `sales` → ไม่ใช่ก็ปฏิเสธ
4. Trigger ตรวจซ้ำว่ายอดรวมไม่เกิน `total_amount` และเขียน `audit_logs`
5. Realtime แจ้งทุกเครื่องที่เปิดอยู่ → โหลดข้อมูลการ์ดนั้นใหม่

**การตรวจในแอปเป็นแค่ความสะดวกของผู้ใช้ ตัวบังคับจริงคือ RLS และ trigger ใน database** เพราะใครก็เรียก API ตรงได้โดยไม่ผ่านแอป

## 4. Login และ role

```
เปิดแอป → มี session ไหม?
  ├─ ไม่มี → หน้า login (อีเมล + รหัสผ่าน)
  └─ มี → อ่าน profiles ของตัวเอง
           ├─ ไม่พบ / is_active = false → ออกจากระบบ + แจ้งเตือน
           └─ role = owner / sales → หน้าตาราง (เมนูตาม role)
```

- **ปิด "Allow new users to sign up"** ใน Supabase Auth ไม่มีหน้าสมัครในแอป
- สร้างบัญชีจาก Supabase dashboard แล้วเพิ่มแถวใน `profiles` พร้อม role (บันทึกขั้นตอนใน progress.md)
- 1 คน = 1 บัญชี ห้ามใช้บัญชีร่วมกัน (ประวัติการแก้ไขต้องบอกได้ว่าใครทำ)
- Session ถูกจำไว้ในเครื่อง ไม่ต้องล็อกอินทุกครั้ง
- **iPhone:** แอปที่ติดตั้งบนหน้าจอ แยกที่เก็บข้อมูลจาก Safari ต้องล็อกอินในแอปที่ติดตั้งอีกครั้งหนึ่ง
- เมนูหรือปุ่มที่ซ่อนตาม role เป็นแค่เรื่องหน้าจอ สิทธิ์จริงอยู่ที่ RLS

## 5. ความปลอดภัย

| กฎ | วิธีบังคับ |
|---|---|
| ไม่มี key ลับในเว็บ | ใช้แค่ `VITE_SUPABASE_URL` และ `VITE_SUPABASE_PUBLISHABLE_KEY`, `.env.local` อยู่ใน `.gitignore` |
| ทุกตารางมี RLS | เปิด automatic RLS ไว้ในโปรเจกต์ + เขียน policy ใน migration พร้อมตาราง |
| ตรวจ role ใน policy | function `public.my_role()` อ่าน role จาก `profiles` ของ `auth.uid()` (security definer) |
| ห้ามลบ | ไม่มี policy DELETE สำหรับใครเลย |
| ประวัติการแก้ไขครบ | trigger บนตารางหลัก เขียน `audit_logs` ทุก insert/update |
| ห้ามแก้ role ตัวเอง | ไม่มี policy UPDATE บน `profiles` |

## 6. เวลาและวันที่

- "วันนี้" = `(now() at time zone 'Asia/Bangkok')::date` คำนวณใน database เท่านั้น
- เครื่องผู้ใช้แสดงวันที่แบบไทย (พ.ศ.) ด้วย `toLocaleDateString('th-TH')`
- เงินคำนวณใน database (`numeric`) แอปแค่จัดรูปแบบตัวเลข ไม่คำนวณยอดเงินด้วย JavaScript

## 7. Realtime

- เปิด Realtime ให้ **4 ตาราง** ใน `004_realtime.sql`: `companies`, `receivables`, `payments`, `audit_logs`
  (`audit_logs` ด้วย เพราะ `"ข้อมูล ณ"` และประวัติการแก้ไขอ่านจากตารางนี้, `companies` เพราะชื่อบริษัทเปลี่ยนได้)
- แอป subscribe การเปลี่ยนแปลง แล้ว**โหลดใหม่จาก view / ตาราง** (`receivable_summary`, `payments`, `audit_logs`)
  **ไม่คำนวณเองจาก event** — event เป็นแค่สัญญาณว่า "มีของใหม่" ค่าเงินและสถานะยังมาจาก database เสมอ
- **รวบ event ที่มาติดกันเป็นการโหลดครั้งเดียว** (หน่วง 400 ms): การบันทึก 1 ครั้งทำให้เกิดหลาย event
  เสมอ (แถวในตารางหลัก + แถวใน `audit_logs` ที่ trigger เขียน)
- **โหลดใหม่เสมอเมื่อกลับมาที่แท็บ / แอป** (`visibilitychange`, `focus`, `pageshow` จาก bfcache)
  **หรือเน็ตกลับมา** (`online`) และเมื่อ channel ต่อใหม่ได้ (`SUBSCRIBED` รอบที่ 2 ขึ้นไป)
  เพราะมือถือมักตัด websocket ตอนพักแอป แล้ว event ช่วงนั้นหายไปเงียบ ๆ — เชื่อ Realtime อย่างเดียวไม่ได้
- **RLS ยังบังคับอยู่:** Realtime ตรวจ policy SELECT เป็นรายแถวก่อนส่ง จึงส่งเฉพาะแถวที่ผู้ใช้มีสิทธิ์อ่าน
  (`anon` ไม่มีสิทธิ์ select ทั้ง 4 ตาราง, ผู้ใช้ที่ `is_active = false` มี `my_role()` เป็น null → ไม่ได้รับอะไร)
  supabase-js ส่ง JWT ของผู้ใช้ให้ Realtime เองตอน `INITIAL_SESSION` / `SIGNED_IN` / `TOKEN_REFRESHED`
- ไม่ตั้ง `replica identity full` (ส่งแค่แถวใหม่) และไม่มี DELETE ในระบบนี้
  จึงไม่ติดข้อจำกัดที่ event ของ DELETE ไม่ผ่าน RLS
- โค้ดอยู่ที่ `src/lib/live.js` (`useLiveReload`) — หน้าตารางและหน้ารายละเอียดใช้ตัวเดียวกัน
- **การ์ดที่เปิดดูอยู่ถูกยกเลิกโดยคนอื่น:** โหลดใหม่แล้วไม่พบใน `receivable_summary`
  → แสดงข้อความแล้วพากลับหน้าตาราง (ตัวกรองเดิม)
- โหลดใหม่ไม่สำเร็จเพราะไม่มีสัญญาณ → แสดงข้อความ "ไม่มีสัญญาณ" + ปุ่มลองอีกครั้ง **แทนตัวเลขเก่า** (เหมือนข้อ 8)
- เป้าหมาย: ฝ่ายขายบันทึกบนมือถือ → หน้าจอเจ้าของอัปเดตโดยไม่ต้องรีเฟรช

## 7.1 เลขเวอร์ชันของแอป

- `src/lib/version.js` export `APP_VERSION` — **ที่เดียวในโปรเจกต์** เปลี่ยนที่นี่ตอนออก V1 / V2
- แสดงท้าย `main` ทุกหน้า และท้ายกล่อง login (class `.app-ver`)
  เพื่อให้ลูกค้าบอกได้ว่ากำลังใช้เวอร์ชันไหนตอนแจ้ง feedback
- `version` ใน `package.json` เป็นข้อมูลของ npm เท่านั้น แอปไม่ได้อ่าน

## 8. PWA

ทำด้วย `vite-plugin-pwa` (ตั้งค่าใน `vite.config.js` ที่เดียว) — manifest และ service worker ถูกสร้างตอน `npm run build`

| ส่วน | ค่า |
|---|---|
| name / short_name | ระบบติดตามยอดค้างชำระ — OK / OK ยอดค้าง |
| display | standalone (เปิดเต็มจอ ไม่มีแถบเบราว์เซอร์) |
| start_url / scope / id | `/` |
| lang | th |
| icons | 192×192, 512×512, maskable 512×512 + `apple-touch-icon` 180×180 สำหรับ iPhone |
| theme_color / background_color | `#1c5da3` (`--primary`) / `#f2f5f4` (`--bg`) จาก ui-reference |
| service worker | **cache แค่ไฟล์ของแอป (app shell)** ห้าม cache ข้อมูลจาก Supabase |

**ไอคอน:** ต้นฉบับคือ `public/logo-ok.svg` (โลโก้ "OK" ตัวเดียวกับในแอป ตัวอักษรเป็นเส้น ไม่ใช่ `<text>` จึงไม่ต้องใช้ฟอนต์)
→ `npm run icons` แปลงเป็น PNG ทุกขนาดลง `public/icons/` ด้วย `scripts/generate-icons.mjs`
แก้โลโก้ = แก้ SVG ไฟล์เดียวแล้วรันสคริปต์ใหม่ **ห้ามเอารูปไอคอนจากอินเทอร์เน็ตมาใส่**

ทำไมห้าม cache ข้อมูล: ถ้ามือถือแสดงยอดเงินเก่าจาก cache เจ้าของอาจเห็นยอดค้างที่จ่ายไปแล้ว ไม่มีสัญญาณเน็ต → แสดงข้อความ "ออฟไลน์" แทนตัวเลขเก่า
วิธีบังคับ: ใน `workbox` ไม่มี `runtimeCaching` เลย service worker จึงรับผิดชอบแค่ไฟล์ที่ precache ไว้ (js/css/html/ไอคอน)
คำขอไป Supabase (ข้อมูล, auth, realtime) และฟอนต์จาก Google เป็นคำขอข้ามโดเมนที่ไม่มี route รองรับ → วิ่งออกเน็ตจริงทุกครั้ง

**อัปเดตเวอร์ชันใหม่:** `registerType: 'prompt'` — deploy ขึ้น Vercel แล้วแอปที่ติดตั้งไว้จะเจอ service worker ตัวใหม่
(ตอนเปิดแอป, ตอนสลับกลับมาที่แอป, ตอนเน็ตกลับมา และทุก 1 ชั่วโมง) แล้วขึ้นแถบ **"มีแอปเวอร์ชันใหม่ · อัปเดตเดี๋ยวนี้ / ไว้ก่อน"**
(`src/components/UpdatePrompt.jsx`) กดอัปเดต = โหลดหน้าใหม่ด้วยเวอร์ชันใหม่ทันที
ถ้าไม่กด ก็ได้เวอร์ชันใหม่เองเมื่อปิดแอปทุกหน้าต่างแล้วเปิดใหม่ — **ไม่ต้องลบแอปออกจากหน้าจอแล้วติดตั้งซ้ำ**
ไม่รีโหลดเองโดยไม่ถาม เพราะผู้ใช้อาจกำลังกรอกฟอร์มการจ่ายอยู่

**แถบสถานะของ iPhone (safe-area):** `viewport-fit=cover` + `apple-mobile-web-app-status-bar-style: default`
และแต่ละส่วนเผื่อขอบปลอดภัยเอง — `.topbar` เผื่อ `env(safe-area-inset-top)`, `main` และ `.login` เผื่อซ้าย/ขวา/ล่าง
(ห้ามใส่ padding ที่ `:root` เพราะ `.topbar` เป็น sticky แล้วจะเว้นซ้ำสองชั้น)

**ติดตั้ง:** iPhone ต้องเปิดผ่าน Safari → แชร์ → Add to Home Screen · Android เปิดผ่าน Chrome → ติดตั้งแอป
iPhone จะเปิดไอคอนบนหน้าจอหลักเป็นแอปแยกจาก Safari ต้องล็อกอินในแอปนั้นอีกครั้ง (ดูข้อ 4)

## 9. โครงสร้างโฟลเดอร์

```
ok-receivables/
├── AGENTS.md                 กฎถาวรสำหรับ AI
├── CLAUDE.md                 ชี้ไปที่ AGENTS.md
├── docs/                     prd, schema, architecture, implementation-plan, progress, ui-reference
├── supabase/
│   ├── migrations/           001_*.sql, 002_*.sql … (รันตามลำดับ)
│   ├── tests/                m1_checks.sql, m2_checks.sql … (ตรวจ RLS แบบ PASS/FAIL)
│   └── seed/                 test_data.sql (ข้อมูล [TEST]), cleanup_test_data.sql (ยกเลิก/ปิด [TEST])
├── vercel.json               rewrite ทุก path → index.html (react-router)
├── scripts/
│   └── generate-icons.mjs    สร้าง PNG ของ PWA จาก public/logo-ok.svg (npm run icons)
├── public/
│   ├── logo-ok.svg           โลโก้ "OK" ต้นฉบับ + favicon (ต้นทางของไอคอนทุกไฟล์)
│   └── icons/                icon-192, icon-512, icon-512-maskable, apple-touch-icon-180 (.png)
└── src/
    ├── main.jsx, App.jsx     จุดเริ่มต้น + routes
    ├── lib/
    │   ├── supabase.js       client
    │   ├── data.js           คำสั่งอ่าน/เขียนทั้งหมด (ที่เดียว)
    │   ├── format.js         จัดรูปแบบเงิน/วันที่ + บวก/เทียบเงินด้วย BigInt
    │   ├── dbError.js        แปล error ของ database เป็นภาษาคน (schema.md ข้อ 6)
    │   ├── history.js        เลือก/จัดรายการประวัติการแก้ไข
    │   ├── toast.js          ข้อความแจ้งผลการบันทึก (แทน window.alert)
    │   ├── live.js           Realtime: subscribe แล้วโหลดใหม่ (รวบ event + ตอนกลับมาที่แอป/เน็ตกลับมา)
    │   ├── version.js        APP_VERSION ("V0.1") — ที่เดียวในโปรเจกต์
    │   ├── focus.js          โฟกัสช่องแรกบนเครื่องที่มีเมาส์
    │   └── i18n.js           ข้อความไทย/อังกฤษ
    ├── auth/                 หน้า login, ตัวจัดการ session/role
    ├── pages/                ReceivablesPage, ReceivableDetailPage, LoginPage
    ├── components/           Card, StatusBars, MonthFilter, EditHistory, Dialog,
    │                         ReceivableForm, PaymentForm, CompaniesDialog, CancelButton,
    │                         UpdatePrompt (แถบ "มีแอปเวอร์ชันใหม่")
    └── index.css             tokens สีและ CSS จาก ui-reference
```

- ฟอร์มทุกตัวเป็น dialog ในแอป (`Dialog.jsx`) ไม่มี `window.alert / confirm / prompt`
  การยกเลิก (soft delete) ใช้ `CancelButton` แบบยืนยัน 2 ขั้นตาม ui-reference
- ปุ่มเพิ่ม/แก้ไขแสดงเฉพาะ `role = sales` — เป็นเรื่องหน้าจอเท่านั้น สิทธิ์จริงอยู่ที่ RLS
- `"ข้อมูล ณ"` = `max(audit_logs.created_at)` (ครอบคลุมทุกการเพิ่ม/แก้/ยกเลิก รวมการ์ดที่ถูกยกเลิก
  ซึ่งหายไปจาก `receivable_summary`)

## 10. Database migrations

- ทุกการเปลี่ยน database = ไฟล์ใหม่ใน `supabase/migrations/` ตั้งชื่อเรียงเลข เช่น `002_rls_policies.sql`
- รันใน Supabase SQL Editor ตามลำดับ แล้วบันทึกใน progress.md ว่ารันไฟล์ไหนแล้ว
- **ห้ามแก้ไฟล์ migration ที่รันไปแล้ว** ต้องการเปลี่ยน → เขียนไฟล์ใหม่
- ห้ามสร้างหรือแก้ตารางด้วยการคลิกในหน้า Supabase เพื่อให้ repo กับ database ตรงกันเสมอ

## 11. สภาพแวดล้อม

| | ที่อยู่ | ค่า env |
|---|---|---|
| เครื่องนักพัฒนา | localhost:5173 | `.env.local` |
| Production | ok-receivables.vercel.app | Vercel Environment Variables |

- มี Supabase โปรเจกต์เดียว เครื่องนักพัฒนาและ production ใช้ database เดียวกัน
- **ก่อนส่งมอบให้ลูกค้า:** เอาข้อมูลทดสอบออกจากหน้าจอทั้งหมดด้วย `supabase/seed/cleanup_test_data.sql`
  (ยกเลิกการจ่าย / การ์ด และปิดบริษัท `[TEST]` — ไม่ใช้ DELETE ตาม AGENTS.md) แล้วบันทึกใน progress.md
- ระหว่างทดสอบกับลูกค้า: ห้ามทดลองบันทึกข้อมูลมั่ว ๆ ใน production ใช้บริษัทชื่อ `[TEST] …` แล้วยกเลิกทิ้ง

## 12. ยังไม่ได้ออกแบบ

- ระบบเก็บ feedback (prd ข้อ 11) — รอคำตอบจากการสัมภาษณ์
