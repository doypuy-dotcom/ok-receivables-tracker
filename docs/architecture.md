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

- เปิด Realtime ให้ตาราง `receivables` และ `payments`
- แอป subscribe การเปลี่ยนแปลง แล้วโหลด `receivable_summary` ใหม่ (ไม่คำนวณเองจาก event)
- เป้าหมาย: ฝ่ายขายบันทึกบนมือถือ → หน้าจอเจ้าของอัปเดตโดยไม่ต้องรีเฟรช

## 8. PWA

| ส่วน | ค่า |
|---|---|
| name / short_name | ระบบติดตามยอดค้างชำระ — OK / OK ยอดค้าง |
| display | standalone (เปิดเต็มจอ ไม่มีแถบเบราว์เซอร์) |
| icons | 192×192, 512×512 + `apple-touch-icon` 180×180 สำหรับ iPhone |
| theme_color | สีหลักจาก ui-reference |
| service worker | **cache แค่ไฟล์ของแอป (app shell)** ห้าม cache ข้อมูลจาก Supabase |

ทำไมห้าม cache ข้อมูล: ถ้ามือถือแสดงยอดเงินเก่าจาก cache เจ้าของอาจเห็นยอดค้างที่จ่ายไปแล้ว ไม่มีสัญญาณเน็ต → แสดงข้อความ "ออฟไลน์" แทนตัวเลขเก่า

**ติดตั้ง:** iPhone ต้องเปิดผ่าน Safari → แชร์ → Add to Home Screen · Android เปิดผ่าน Chrome → ติดตั้งแอป

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
├── public/                   ไอคอน PWA, favicon
└── src/
    ├── main.jsx, App.jsx     จุดเริ่มต้น + routes
    ├── lib/
    │   ├── supabase.js       client
    │   ├── data.js           คำสั่งอ่าน/เขียนทั้งหมด (ที่เดียว)
    │   ├── format.js         จัดรูปแบบเงิน/วันที่ + บวก/เทียบเงินด้วย BigInt
    │   ├── dbError.js        แปล error ของ database เป็นภาษาคน (schema.md ข้อ 6)
    │   ├── history.js        เลือก/จัดรายการประวัติการแก้ไข
    │   ├── toast.js          ข้อความแจ้งผลการบันทึก (แทน window.alert)
    │   ├── focus.js          โฟกัสช่องแรกบนเครื่องที่มีเมาส์
    │   └── i18n.js           ข้อความไทย/อังกฤษ
    ├── auth/                 หน้า login, ตัวจัดการ session/role
    ├── pages/                ReceivablesPage, ReceivableDetailPage, LoginPage
    ├── components/           Card, StatusBars, MonthFilter, EditHistory, Dialog,
    │                         ReceivableForm, PaymentForm, CompaniesDialog, CancelButton
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
