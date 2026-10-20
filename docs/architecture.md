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
| ส่งออก JPG / PDF | `html-to-image` 1.11 → JPG, `jspdf` 4.2 ใส่รูปนั้น → PDF | ทำในเบราว์เซอร์ ไม่ต้องมีเซิร์ฟเวอร์, แปลงเป็นรูปก่อนทำให้ภาษาไทยไม่เพี้ยนใน PDF |
| ฟอนต์ | Anuphan (Google Fonts) | อ่านภาษาไทยชัด ตรงกับ ui-reference |

- **2 ไลบรารีของการส่งออกถูกโหลดตอนกดปุ่มเท่านั้น** (`await import()` ใน `src/lib/exportSheet.js`)
  รวมกันเกือบ 600 KB (jspdf + html2canvas ที่มันพาไป) ซึ่งใหญ่กว่าตัวแอปทั้งตัว
  ถ้า import ตรง ๆ ทุกคนจะต้องโหลดทั้งที่ส่วนใหญ่เปิดแอปมาดูยอด ไม่ได้ส่งออกไฟล์
  → `npm run build` แยกเป็น chunk ของตัวเอง หน้าอื่นไม่แบกน้ำหนักนี้
- **ภาษาไทยในไฟล์ที่ส่งออก:** รอ `document.fonts.ready` → ฝัง `@font-face` ของ Anuphan เป็น
  data URI ลงในรูป (`getFontEmbedCSS`) → ถ่ายทิ้งรอบแรกก่อน 1 ครั้ง (ข้อจำกัดของ html-to-image
  บน iOS Safari ที่รูปแรกมักออกมาก่อนฟอนต์เข้าที่) · ไม่มีสัญญาณ = ไม่ปล่อยไฟล์ เพราะฟอนต์จะผิด
- **ขนาดกระดาษในไฟล์มาจาก DOM จริง** 794 × 1123 px (A4 ที่ 96dpi) ถ่ายที่ `pixelRatio: 2` ≈ 192dpi
  **ไม่มี layout ที่สองสำหรับไฟล์** (AGENTS.md) มือถือย่อด้วย `transform: scale()` ที่กล่องนอก
  ตัวกระดาษยังกว้าง 794px เสมอ จึงได้ไฟล์ขนาดเดียวกันทุกเครื่อง

## 3. การไหลของข้อมูล

**อ่าน (เปิดหน้าตาราง)**
1. แอปเรียก `receivable_summary` ผ่าน supabase-js พร้อม session ของผู้ใช้
2. RLS ตรวจว่าผู้ใช้ล็อกอินและ `is_active` → ส่งข้อมูลกลับ
3. ค่าคำนวณทั้งหมด (ยอดคงเหลือ, % แถบ, เลยกำหนด, ค้างข้ามเดือน) มาจาก view แอปแค่แสดงผล

**อ่าน (เปิดหน้าสรุปรายเดือน — V2)**
1. แอปเรียก 3 view ของ `006` พร้อมกัน: `monthly_report`, `monthly_report_total`, `report_asof`
   (schema.md ข้อ 4.3) — ยอดเงินอ่านเป็น `::text` เหมือนที่อื่น เพื่อไม่ให้ JSON แปลงเป็น float
2. RLS ของ `receivable_summary` ที่อยู่ข้างใต้ยังบังคับเหมือนเดิม (view ใช้ `security_invoker`)
3. แอป**กรองแถวตามเดือนที่เลือกและจัดรูปแบบเท่านั้น** ยอดรวม ลำดับ และวันที่ "ดู ณ"
   มาจาก database ทั้งหมด **ห้ามบวกหรือเทียบเงินใน JavaScript** (AGENTS.md)

**อ่าน (เปิดหน้าสถิติ — V2)**
1. แอปเรียก 5 view ของ `008` พร้อมกัน (`stats_overview`, `stats_collection_by_month`,
   `stats_aging`, `stats_company_behavior`, `stats_company_balance` — schema.md ข้อ 4.5)
   พร้อม `report_asof` ของ `006` สำหรับบรรทัด "ดู ณ"
2. ทั้ง 5 view อ่านต่อจาก `stats_cards` → `receivable_summary` → RLS ของตารางจริงยังบังคับเหมือนเดิม
3. แอป**เลือกแถวของเดือนที่กด เลือก 5 อันดับแรก และจัดรูปแบบตัวเลขเท่านั้น** —
   ยอดเงิน, %, ค่าเฉลี่ย, การจัดกลุ่มอายุหนี้, ลำดับบริษัท และความกว้างของแถบกราฟ
   มาจาก database ทั้งหมด **ห้ามคำนวณใน JavaScript** (AGENTS.md)

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
| หมายเหตุและ feedback แก้/ลบไม่ได้ | ไม่มี policy UPDATE / DELETE บน `receivable_notes`, `app_feedback` (append-only — schema.md 3.6) |
| เจ้าของเขียนได้แค่หมายเหตุ | policy INSERT ของ `receivable_notes` เปิดให้ทุก role ที่ `is_active` (007) ส่วน `companies` / `receivables` / `payments` ยังเป็น `my_role() = 'sales'` |
| feedback เห็นได้แค่เจ้าของคำตอบ | policy SELECT ของ `app_feedback` คือ `user_id = auth.uid()` |

## 6. เวลาและวันที่

- "วันนี้" = `(now() at time zone 'Asia/Bangkok')::date` คำนวณใน database เท่านั้น
- เครื่องผู้ใช้แสดงวันที่แบบไทย (พ.ศ.) ด้วย `toLocaleDateString('th-TH')`
- เงินคำนวณใน database (`numeric`) แอปแค่จัดรูปแบบตัวเลข ไม่คำนวณยอดเงินด้วย JavaScript

## 7. Realtime

- เปิด Realtime ให้ **5 ตาราง**: `companies`, `receivables`, `payments`, `audit_logs` ใน `004_realtime.sql`
  และ `receivable_notes` ใน `005_notes_and_feedback.sql`
  (`audit_logs` ด้วย เพราะ `"ข้อมูล ณ"` และประวัติการแก้ไขอ่านจากตารางนี้, `companies` เพราะชื่อบริษัทเปลี่ยนได้,
  `receivable_notes` เพราะฝ่ายขายเขียนหมายเหตุบนคอมแล้วเจ้าของต้องเห็นบนมือถือทันที
  และตั้งแต่ 007 เจ้าของก็เขียนได้ด้วย ฝ่ายขายจึงต้องเห็นของเจ้าของทันทีเหมือนกัน)
- **`app_feedback` ไม่เปิด Realtime:** ไม่มีหน้าจอไหนต้องอัปเดตตาม และอ่านได้แค่แถวของตัวเอง
- แอป subscribe การเปลี่ยนแปลง แล้ว**โหลดใหม่จาก view / ตาราง**
  (`receivable_summary`, `receivable_latest_note`, `payments`, `audit_logs`, `receivable_notes`)
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
- โค้ดอยู่ที่ `src/lib/live.js` (`useLiveReload`) — หน้าตาราง หน้ารายละเอียด และ
  **หน้าสรุปรายเดือน (V2)** ใช้ตัวเดียวกัน · หน้าสรุปรายเดือนโหลดใหม่ทั้ง 3 view รวม `report_asof`
  จึงได้ทั้งตัวเลขใหม่และเวลา "ดู ณ" ใหม่ (ลูกค้าสั่งว่ารายงานต้องเป็นข้อมูลล่าสุดเสมอ — prd.md ข้อ 6.1)
- **การ์ดที่เปิดดูอยู่ถูกยกเลิกโดยคนอื่น:** โหลดใหม่แล้วไม่พบใน `receivable_summary`
  → แสดงข้อความแล้วพากลับหน้าตาราง (ตัวกรองเดิม)
- โหลดใหม่ไม่สำเร็จเพราะไม่มีสัญญาณ → แสดงข้อความ "ไม่มีสัญญาณ" + ปุ่มลองอีกครั้ง **แทนตัวเลขเก่า** (เหมือนข้อ 8)
- เป้าหมาย: ฝ่ายขายบันทึกบนมือถือ → หน้าจอเจ้าของอัปเดตโดยไม่ต้องรีเฟรช

- **หน้าสถิติใช้ `useLiveReload` ตัวเดียวกัน** (V2 ข้อ 3) ไม่ต้องเพิ่มตารางใน publication เลย
  เพราะ view ของ `008` อ่านต่อจาก `receivables` / `payments` / `companies` ที่ subscribe อยู่แล้ว
  → ฝ่ายขายบันทึกการจ่าย ตัวเลขสถิติบนจอเจ้าของเปลี่ยนเองโดยไม่ต้องรีเฟรช

## 7.1 เลขเวอร์ชันของแอป

- `src/lib/version.js` export `APP_VERSION` — **ที่เดียวในโปรเจกต์** (ตอนนี้ `V2`) เปลี่ยนที่นี่ทุกครั้งที่ส่งมอบเวอร์ชันใหม่
  ค่านี้ถูกแนบไปกับทุกแถวของ `app_feedback` ด้วย (prd.md ข้อ 11) เพื่อเทียบผลแต่ละเวอร์ชัน
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
│   ├── tests/                m1_checks.sql … stats_checks.sql (ตรวจ RLS / กฎ แบบ PASS/FAIL)
│   ├── queries/              feedback_report.sql (สรุป feedback แยกตามเวอร์ชัน × role — อ่านอย่างเดียว)
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
    │   ├── version.js        APP_VERSION ("V2") — ที่เดียวในโปรเจกต์
    │   ├── exportSheet.js    ถ่าย .sheet เป็น JPG / PDF (โหลดไลบรารีตอนกดปุ่ม)
    │   ├── fitText.js        ย่อตัวอักษรของเซลล์ให้ชื่อบริษัทแสดงครบในรายงาน
    │   ├── focus.js          โฟกัสช่องแรกบนเครื่องที่มีเมาส์
    │   └── i18n.js           ข้อความไทย/อังกฤษ
    ├── auth/                 หน้า login, ตัวจัดการ session/role
    ├── pages/                ReceivablesPage, ReceivableDetailPage, MonthlyReportPage,
    │                         StatsPage (หน้าสถิติ), LoginPage
    ├── components/           Card, StatusBars, MonthFilter, EditHistory, Dialog,
    │                         ReceivableForm, PaymentForm, CompaniesDialog, CancelButton,
    │                         DateField (ช่องวันที่ของแอป), NotesPanel (หมายเหตุบนการ์ด),
    │                         FeedbackDialog (ส่งความคิดเห็น), UpdatePrompt (แถบ "มีแอปเวอร์ชันใหม่"),
    │                         ReportSheet (กระดาษ A4 ของหน้าสรุปรายเดือน = DOM ที่ถูกถ่ายเป็นไฟล์),
    │                         StatBar (แถบสัดส่วนของหน้าสถิติ — CSS ล้วน ไม่มีไลบรารีกราฟ)
    └── index.css             tokens สีและ CSS จาก ui-reference
```

- ฟอร์มทุกตัวเป็น dialog ในแอป (`Dialog.jsx`) ไม่มี `window.alert / confirm / prompt`
  การยกเลิก (soft delete) ใช้ `CancelButton` แบบยืนยัน 2 ขั้นตาม ui-reference
- ปุ่มเพิ่ม/แก้ไขแสดงเฉพาะ `role = sales` — เป็นเรื่องหน้าจอเท่านั้น สิทธิ์จริงอยู่ที่ RLS
- **เมนู 3 หน้าใต้ส่วนหัว** (`SubNav` ใน `App.jsx`): "ตารางยอดค้าง" (`/`, รวม `/r/:id`),
  "สรุปรายเดือน" (`/report`) และ "สถิติ" (`/stats`) — ทั้งเจ้าของและฝ่ายขายเข้าได้ทั้ง 3 หน้า
  **หน้าสรุปรายเดือนและหน้าสถิติอ่านอย่างเดียวสำหรับทุกคน** (ชั้น database ให้แต่สิทธิ์ `select`
  — schema.md ข้อ 4.3 และ 4.5) ไม่ใช่แค่ไม่มีปุ่มบนหน้าจอ
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

- (ว่าง) — ระบบเก็บ feedback ออกแบบและทำแล้วใน V1 รอบ ข (prd ข้อ 11, schema.md ข้อ 3.7)
