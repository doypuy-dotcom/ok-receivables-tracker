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


## Feedback รอบ 0 — ฝ่ายขายดูเดโม (5 ต.ค. 2569)
แหล่งที่มา: docs/interviews/sales-interview-2026-10-05.pdf

| # | feedback | ตัดสินใจ |
|---|---|---|
| 1 | เพิ่มรายละเอียดเช็ค: ธนาคาร, สาขา, เลขเช็ค | V1 |
| 2 | ใส่วันรับเช็คก่อน แล้วแก้เป็นวันที่บนเช็คทีหลัง | V0.1 รองรับแล้ว (แก้ผ่านปุ่มแก้ไขยอดค้าง) |
| 3 | สถานะบอกว่าเลทนับจากวันรับเช็คหรือวันที่บนเช็ค | V1 |
| 3a | 1 การ์ดมีเช็คได้หลายใบ นับเลทจากเช็คใบแรก | V1 (ต้องมีตารางเช็คแยก) |
| 3b | หมายเหตุ เช่น ลูกค้าขอเลื่อน | รวมในข้อ 4 |
| 4 | ช่องความคิดเห็นบนการ์ด แบบประวัติเรียงตามเวลา (ใคร + เมื่อไหร่ + ข้อความ) ฝ่ายขายเขียน เจ้าของอ่านอย่างเดียว | V0.1 ถ้ามีเวลาหลัง M5 ไม่งั้น V1 |

## สัมภาษณ์เจ้าของ (6 ต.ค. 2569)
แหล่งที่มา: docs/interviews/owner-interview-2026-10-06.pdf
- เจ้าของเลือกเรื่องลูกหนี้เองเป็นเรื่องแรกที่ควรทำ (สต็อกสำคัญแต่ใหญ่เกินไป → out of scope)
- ต้องการเห็นเงินเข้าทันทีบนมือถือ เพราะไม่ได้เข้าบริษัททุกวัน → M5 realtime ห้ามตัดจาก V0.1
- ต้องการให้ฝ่ายขายรายงานความคืบหน้าได้โดยไม่ต้องถาม → ตรงกับ feedback ข้อ 4
- ตกลงจ่าย ฿500 สำหรับทดลองใช้ 2 สัปดาห์

## หมายเหตุจากอาจารย์ (6 ต.ค.)
- อนุญาตให้ใช้คลิปเสียงแทนวิดีโอสำหรับการสัมภาษณ์
- ยอดชำระขั้นต่ำ ฿500 ผ่านเกณฑ์

## M1 — Login + role ✅ (2026-10-06)

### ทำอะไรไปแล้ว

**Database**
- `supabase/migrations/001_profiles_and_roles.sql`
  - enum `user_role` ('owner', 'sales'), ตาราง `profiles` ตาม schema.md 3.1 (FK → `auth.users`, ไม่มี cascade)
  - `public.my_role()`: `security definer`, `stable`, `set search_path = ''` คืน role ของ `auth.uid()` เฉพาะ `is_active` (ไม่งั้น null)
    execute ได้เฉพาะ `authenticated` (revoke จาก public, anon)
  - RLS เปิด, policy เดียว: SELECT สำหรับ `authenticated` เมื่อ `my_role() is not null` (ผู้ใช้ที่ active อ่านได้ทุกแถว)
  - ไม่มี policy INSERT / UPDATE / DELETE + revoke สิทธิ์ตารางจาก anon/authenticated เหลือแค่ SELECT ของ authenticated
- `supabase/tests/m1_checks.sql`: ตรวจ PASS/FAIL 13 ข้อ (role, อ่าน, แก้ role ตัวเอง, insert, delete, anon, ไม่มี profile, is_active = false)
  ทุกการเขียนถูก rollback ไม่เปลี่ยนข้อมูลจริง
  - ทดสอบในเครื่องด้วย PGlite + stub `auth` schema แล้ว: 13/13 PASS และเมื่อจงใจเปิด policy UPDATE ผิด ๆ ข้อ 4–7 ขึ้น FAIL ถูกต้อง
  - **ยังไม่ได้รันบน Supabase จริง**

**App**
- `react-router-dom` 7: `/login`, `/` (ต้องล็อกอิน), path อื่น → `/`
- `vercel.json`: rewrite ทุก path ไป `index.html` (เปิด/รีเฟรช `/login` ตรง ๆ บน Vercel ได้)
- `src/auth/AuthProvider.jsx` + `useAuth.js`: ตาม architecture.md ข้อ 4
  - session จำในเครื่อง (ค่าเริ่มต้นของ supabase-js, localStorage)
  - มี session → อ่าน `profiles` ของตัวเอง → ไม่พบ / `is_active = false` → ออกจากระบบ + ข้อความในหน้า login
    (RLS ไม่คืนแถวให้ผู้ใช้ที่ปิดใช้งาน จึงแยก "ไม่มี profile" กับ "ถูกปิด" ไม่ได้ ใช้ข้อความเดียวกัน)
  - โหลด profile ไม่ได้ (เน็ตหลุด) → หน้าข้อความ + ปุ่ม "ลองอีกครั้ง" / "ออกจากระบบ" (ไม่บังคับออก)
  - ออกจากระบบใช้ `scope: 'local'` ออกเฉพาะเครื่องนี้ ไม่เตะอีกเครื่องของผู้ใช้คนเดียวกัน
- `src/auth/RequireAuth.jsx`: ป้องกันหน้าที่ต้องล็อกอิน + สถานะกำลังโหลด
- `src/pages/LoginPage.jsx`: อีเมล + รหัสผ่าน หน้าตาตาม `.login-box` ของ ui-reference (ไม่มีหน้าสมัคร)
  ข้อความ error: ไม่กรอก, รหัสผิด, ยังไม่ยืนยันอีเมล, ลองบ่อยเกิน, ไม่มีสัญญาณ
- `src/components/Header.jsx`: โลโก้ + ชื่อบริษัท | ปุ่มชื่อ + ตำแหน่ง ▾ (เมนู: ชื่อ, ตำแหน่ง, ออกจากระบบ) | ปุ่มภาษา
- `src/pages/ReceivablesPage.jsx`: placeholder "ตารางยอดค้าง (M3)" + pill ตำแหน่ง
- `src/lib/i18n.js`: ข้อความไทย/อังกฤษเฉพาะของ M1 + ปุ่ม ENG/ไทย (ui-reference มีปุ่มนี้ใน header และหน้า login)
  ข้อความของหน้าอื่นเพิ่มใน M3
- `src/index.css`: นำ style ของ header, user menu, login, field, btn, pill จาก ui-reference มาใช้ ลบ style หน้าเช็คการเชื่อมต่อของ M0

### ตรวจแล้วว่าผ่าน
- `npm run build` ผ่าน, `npm run lint` ไม่มี warning/error
- `m1_checks.sql` 13/13 PASS บน PGlite (ไม่ใช่ Supabase จริง)

### ต้องทำใน Supabase dashboard (ขั้นตอนสร้างบัญชี — ใช้ซ้ำตอนสร้างบัญชีจริงก่อน V0.1)
1. Authentication → Sign In / Providers: ปิด **Allow new users to sign up**, Email provider เปิดอยู่
2. SQL Editor: รัน `001_profiles_and_roles.sql`
3. Authentication → Users → Add user → Create new user: ใส่อีเมล + รหัสผ่าน, ติ๊ก **Auto Confirm User**
4. SQL Editor: เพิ่มแถว `profiles` จากอีเมล
   ```sql
   insert into public.profiles (id, display_name, role)
   select id, 'ชื่อที่แสดง', 'sales' from auth.users where email = 'อีเมล';
   ```
5. ปิดบัญชี: `update public.profiles set is_active = false where id = (select id from auth.users where email = 'อีเมล');`

### Migrations ที่รันแล้ว
- [x] `001_profiles_and_roles.sql` — รันบน Supabase แล้ว (2026-10-06)
- สร้างผู้ใช้ทดสอบ 2 คน (owner, sales) + แถว `profiles` แล้ว

### ผลทดสอบ (Definition of done)
- [x] ล็อกอิน owner + sales พร้อมกันในคนละเบราว์เซอร์ เห็นชื่อ/ตำแหน่งถูก
- [x] รหัสผิด → ข้อความชัดเจน
- [x] `is_active = false` → รีเฟรชแล้วถูกพาออกจากระบบพร้อมข้อความถูกต้อง (เปิดบัญชีคืนแล้ว)
- [x] ปิดแท็บแล้วเปิดใหม่ → ยังล็อกอินอยู่
- [x] ออกจากระบบ → กลับหน้า login
- [x] `m1_checks.sql` บน Supabase จริง 13/13 PASS
- [x] มือถือ (Vercel): ล็อกอินได้, รีเฟรชไม่ขึ้น 404, ไม่มี error ใน console
- [x] commit

## M2 — ตาราง + RLS + trigger ✅ (2026-10-06)

### ทำอะไรไปแล้ว

**Database — `supabase/migrations/002_core_tables.sql`**
- enums `payment_method`, `audit_action`
- ตาราง `companies`, `receivables`, `payments`, `audit_logs` ตาม schema.md 3.2–3.5
  - `created_at/created_by/updated_at/updated_by` not null, `*_by` FK → `profiles`
  - ตั้งชื่อ constraint ทุกตัว (ให้ M4 แปล error ได้), unique index `receivables_one_per_company_month`
  - `companies_name_trimmed`: ชื่อบริษัทห้ามว่าง / มีแต่ช่องว่าง / มีช่องว่างหน้าหรือหลัง
  - index `payments(receivable_id)`, `audit_logs(receivable_id, created_at)`
- Trigger (เรียงตามชื่อ `trg_10_*` → `trg_20_*` → `trg_90_*`)
  - `set_row_meta`: ใส่ `created_*/updated_*` จาก `auth.uid()`, ล็อก `id/created_*` ตอนแก้ไข, ไม่มีผู้ใช้ → `not_authenticated`
  - `check_payment_rules`: ห้ามเปลี่ยน `receivable_id`, ห้ามเพิ่มการจ่ายในการ์ดที่ยกเลิก,
    ยอดรวมห้ามเกิน `total_amount` (ไม่นับยอดเดิมของตัวเอง, `for update` ล็อกการ์ดกันบันทึกพร้อมกัน)
  - `check_receivable_total`: ห้ามลด `total_amount` ต่ำกว่ายอดที่จ่ายแล้ว
  - `write_audit_log`: ทุก insert/update บน 3 ตาราง พร้อม `receivable_id`, action create/update/cancel
  - trigger ที่รวมยอด / เขียน audit เป็น `security definer`, revoke execute ของ trigger functions จากทุก role
- RLS: อ่าน = ผู้ใช้ active ทุกคน, เพิ่ม/แก้ = sales เท่านั้น, `audit_logs` อ่านอย่างเดียว, ไม่มี DELETE ให้ใคร
  + revoke สิทธิ์ตารางจาก anon, authenticated ได้แค่ select/insert/update (audit_logs: select)
- View `receivable_summary` (`security_invoker = true`, วันนี้ = เวลาไทย): ค่าคำนวณทั้งหมดตาม schema.md 4 + `company_name`
  % เป็น 0–100 ตัดทศนิยมทิ้ง 2 ตำแหน่ง
- รายการ error code / message สำหรับ M4 อยู่ใน schema.md ข้อ 6

**Tests — `supabase/tests/m2_checks.sql`**: ตรวจ PASS/FAIL 39 ข้อ (ข้อทดสอบ 1–8 ของแผน + owner อ่านได้แต่เขียนไม่ได้
+ กฎยอดเงิน, การ์ดที่ยกเลิก, ชื่อบริษัท, ย้ายการจ่าย, ไม่มีผู้ใช้ล็อกอิน, anon, is_active = false) ทุกการเขียนถูก rollback
- ตรวจกับ PGlite ในเครื่องด้วย: จงใจทำ migration ผิด (ลบ security_invoker, นับยอดเดิมซ้ำ, เปิด DELETE, ลบกฎชื่อ / receivable_id) → ข้อที่เกี่ยวข้องขึ้น FAIL ถูกต้อง

**Docs**: schema.md อัปเดตให้ตรงกับ migration (not null ของ `*_by`, กฎชื่อบริษัท, `receivable_id` เปลี่ยนไม่ได้,
คอลัมน์ view + กฎ %, ตาราง error)

### สิ่งที่ต้องรู้สำหรับ milestone ถัดไป
- **เขียนข้อมูลจาก SQL Editor ต้องตั้งผู้ใช้ก่อน** (ไม่งั้น `not_authenticated`) เช่นตอนใส่ข้อมูล `[TEST]` ใน M3:
  ```sql
  select set_config('request.jwt.claims', json_build_object('sub', (select id from auth.users where email = 'อีเมล sales'))::text, true);
  insert into public.companies (name) values ('[TEST] ...');
  ```
  (รันในคำสั่งชุดเดียวกัน เพราะ `true` = มีผลแค่ใน transaction นั้น)
- ทุก update เขียน audit แม้ค่าไม่เปลี่ยน → หน้าประวัติใน M3 ต้องกรองรายการที่ไม่มีช่องไหนเปลี่ยนออก
- ยังไม่ได้เปิด Realtime ให้ `receivables` / `payments` (M5)

### Migrations ที่รันแล้ว
- [x] `002_core_tables.sql` — รันบน Supabase แล้ว (2026-10-06)

### ผลทดสอบ (Definition of done)
- [x] `m2_checks.sql` บน Supabase จริง 39/39 PASS (owner + sales)
- [x] ทุกช่องในตารางสิทธิ์ (prd.md ข้อ 9) ที่ M2 แตะ ทดสอบด้วย role ผิดแล้วถูกปฏิเสธ (ข้อ 9–13, 21–28)
- [x] ไม่มี secret ใน repo, อีเมลใน test เป็น placeholder
- [ ] ทดสอบในเบราว์เซอร์ / มือถือ — M2 ยังไม่มีหน้าจอ เริ่มใน M3
- [x] commit

## M3 — หน้าจอหลัก ✅ (2026-10-06)

### ทำอะไรไปแล้ว

**Database — `supabase/migrations/003_summary_paid_late.sql`** (ตัดสินใจกับผู้ใช้แล้ว)
- `create or replace view receivable_summary` เพิ่ม 2 คอลัมน์ท้าย: `paid_late_actual_days`, `paid_late_credit_days`
  (= `paid_in_full_date` − วันครบกำหนด, ว่างถ้ายังจ่ายไม่ครบ) ใช้แสดง "ตรงเวลา / ช้ากว่ากำหนด N วัน" ในการ์ดจ่ายแล้วและสรุปผล
  คอลัมน์เดิมไม่เปลี่ยน, ยังเป็น `security_invoker = true`, ไม่แตะตาราง — schema.md ข้อ 4 อัปเดตแล้ว
- `supabase/tests/m3_checks.sql`: 5 ข้อ PASS/FAIL (จ่ายตรงเวลา / ช้า / บางส่วน / ยังไม่จ่าย / anon อ่านไม่ได้) rollback ทุกอย่าง

**ข้อมูลทดสอบ — `supabase/seed/`**
- `test_data.sql`: บริษัท `[TEST] …` 10 บริษัท ทุกการเขียนทำในนาม sales ผ่าน `request.jwt.claims` + `set local role authenticated`
  (ผ่าน RLS และ trigger จริง ประวัติจึงเป็นชื่อ sales) วันที่ทั้งหมดนับจากวันนี้เวลาไทย
  - ยังไม่จ่าย, จ่ายบางส่วน (จ่ายเดือนก่อน + เดือนนี้), เลยกำหนด, ค้างข้ามเดือน 1 (เดือนก่อน), ค้างข้ามเดือน 2 (2 เดือนก่อน),
    จ่ายแล้ว ตรงเวลา, จ่ายแล้ว ช้า (เดือนก่อน), เดือนหน้า, มีประวัติการแก้ไข, ยกเลิกแล้ว (ต้องไม่โผล่)
  - "มีประวัติการแก้ไข": แก้การ์ด 2 ครั้ง + update ที่ไม่มีอะไรเปลี่ยน 1 ครั้ง (ต้องไม่โผล่) + แก้การจ่าย + ยกเลิกการจ่าย
    แต่ละขั้นแยก transaction (`now()` ใน transaction เดียวกันเท่ากันหมด)
  - มี `[TEST]` ที่ยังไม่ cleanup อยู่ → หยุด ไม่ใส่ซ้ำ; รันใหม่หลัง cleanup → ชื่อมีเวลาต่อท้าย (ชื่อบริษัทห้ามซ้ำ)
- `cleanup_test_data.sql`: ยกเลิกการจ่าย → ยกเลิกการ์ด → ปิดบริษัท `[TEST]%` (ไม่มี DELETE) ในนาม sales, รันซ้ำได้,
  ตรวจท้ายไฟล์ว่าเหลือ 0 ทั้ง 3 ช่อง ไม่งั้น rollback · architecture.md / implementation-plan.md เปลี่ยนคำว่า "ลบ" เป็นวิธีนี้แล้ว

**App**
- `/` `ReceivablesPage`: ตัวกรองเดือน (ทุกเดือน / หลายเดือน / เฉพาะที่ยังค้าง) ตาม `due_month`, ค่าเริ่มต้น = เดือนนี้ (เวลาไทย)
  ตัวกรองเก็บใน URL (`?m=2026-10-01,2026-11-01` / `?m=all`, `&unpaid=1`) กดกลับจากหน้ารายละเอียดแล้วยังอยู่
  - "ข้อมูล ณ" = `updated_at` ล่าสุดของ `receivable_summary` และ `payments` (การแก้การจ่ายไม่เปลี่ยน `updated_at` ของการ์ด)
  - กล่องยอดรวม 2 กล่อง: บวก `balance::text` ด้วย BigInt หน่วยสตางค์ (ตัดสินใจกับผู้ใช้แล้ว) ไม่ใช้ float
  - การ์ดค้างข้ามเดือน (`is_carried_over`) ปักบนสุดเสมอไม่ว่าเลือกเดือนไหน พร้อมหมายเหตุ "ยอดค้างข้ามเดือนของเดือน … ค้าง … บาท"
  - การ์ดปกติ + แถบ 3 แถบ, การ์ดจ่ายแล้ว + ปุ่มสรุปผล (dialog ในแอป)
- `/r/:id` `ReceivableDetailPage`: ยอดคงเหลือ, แถบ 3 แถบ / ข้อมูลจ่ายครบ, ข้อมูลยอดค้าง, รายการเงินเข้า (กรองเดือนตาม `paid_date`),
  ประวัติการแก้ไข (schema.md 3.5): แก้ไข/ยกเลิก การ์ดและการจ่าย, กรองรายการที่ไม่มีช่องไหนเปลี่ยน, แสดง ใคร · เมื่อไหร่ · ช่อง: ค่าเดิม → ค่าใหม่
  (การจ่ายแสดงว่าเป็นรายการไหน: วิธีจ่าย · ยอด · วันที่) ชื่อบริษัทเดิม (ถ้าเปลี่ยนบริษัท) อ่านจาก audit_logs ของ companies
- อ่านจาก `receivable_summary`, `payments`, `audit_logs` (+ `profiles` สำหรับชื่อคนแก้) เท่านั้น เงินและ % ขอเป็น `::text`
  % แสดงเลขเต็มโดยตัดทศนิยม (99.99 → 99%) ไม่ปัด
- ทุกหน้ามี loading / empty / error (ไม่มีสัญญาณ, ไม่มีสิทธิ์, โหลดไม่สำเร็จ + ปุ่มลองอีกครั้ง)
- ไฟล์ใหม่: `src/lib/format.js`, `data.js`, `history.js`, `src/components/{StatusBars,ReceivableCard,MonthFilter,Dialog,SummaryDialog,PaymentList,EditHistory}.jsx`,
  `src/pages/ReceivableDetailPage.jsx` · แก้: `App.jsx` (route `/r/:id`), `ReceivablesPage.jsx`, `i18n.js`, `index.css`

### ตรวจแล้วว่าผ่าน (ในเครื่อง)
- `npm run lint` 0 warning, `npm run build` ผ่าน (มีคำเตือน chunk > 500 kB — ยังไม่แก้)
- PGlite + stub `auth`: 001 → 002 → `m2_checks` 39/39 → 003 → `m2_checks` 39/39 → `m3_checks` 5/5
  → `test_data.sql` ได้ 9 การ์ดในหน้าจอ สถานะถูกทุกใบ → รันซ้ำถูกปฏิเสธ → `cleanup` เหลือ 0/0/0 → cleanup ซ้ำ 0/0/0 → seed ใหม่ได้
- ผลรวมยอดใน JS (BigInt) ตรงกับ `sum(balance)` ของ database, `buildHistory` กับ audit จริงของ seed: 5 แถว → แสดง 4 (ตัด no-op)
- PGlite ให้ `now()` เดียวกันทั้งไฟล์ จึงยืนยันลำดับประวัติใน seed ไม่ได้ในเครื่อง → ยืนยันบน Supabase จริงแล้ว (ประวัติ 4 รายการถูก)

### ขั้นตอนทดสอบ (2 บัญชี)
**เตรียม (SQL Editor)**
1. รัน `003_summary_paid_late.sql`
2. แก้อีเมลใน `m3_checks.sql` แล้วรัน → 5/5 PASS (จะรัน `m2_checks.sql` ซ้ำด้วยก็ได้ → 39/39)
3. แก้ `sales_email` ใน `test_data.sql` แล้วรันทั้งไฟล์ → ตารางท้ายไฟล์มี 9 แถว

**เบราว์เซอร์ A (คอม) = owner, เบราว์เซอร์ B (มือถือ หรือ incognito) = sales** — ทำข้อ 4–9 ทั้ง 2 บัญชี ต้องเห็นเหมือนกัน
4. หน้าตาราง (ค่าเริ่มต้น = ต.ค. 2569):
   - "ข้อมูล ณ" = เวลาที่รัน seed
   - บนสุด "ยอดค้างข้ามเดือน" 2 ใบ: หมายเหตุ "…ของเดือน สิงหาคม 2569 ค้าง 9,876.54 บาท" และ "…กันยายน 2569 ค้าง 50,000.00 บาท"
   - กล่องซ้าย 174,150.25 บาท · 4 รายการ, กล่องขวา (สีแดง) 59,876.54 บาท · 2 รายการ (ยอดเงินไม่ขึ้นกับวันที่รัน)
   - "[TEST] เลยกำหนด" ขอบซ้ายแดง ข้อความแดง "เลยครบกำหนด … วัน จากวันจริง / จากวันเครดิต"
   - "[TEST] จ่ายแล้ว ตรงเวลา" ขอบเขียว "จ่ายแล้ว" → กด "สรุปผล" → 2 ครั้ง, ตรงเวลาทั้ง 2 แบบ, ปิดด้วย × / ปุ่มปิด / Esc / แตะพื้นหลัง
   - ไม่มี "[TEST] ยกเลิกแล้ว" ที่ไหนเลย
5. ตัวกรอง: ติ๊ก ก.ย. เพิ่ม → ป้าย "2 เดือน", มี "[TEST] จ่ายแล้ว ช้า" (ช้ากว่ากำหนด 15 วัน วันจริง / 12 วัน วันเครดิต)
   → "ทุกเดือน" → มี "[TEST] เดือนหน้า" → "เฉพาะที่ยังค้างชำระ" → การ์ดจ่ายแล้วหาย การ์ดค้างข้ามเดือนยังอยู่
   → ยกเลิกทุกเดือนที่เลือก → กลับเป็น "ทุกเดือน" · แตะนอกกล่องตัวกรองแล้วปิด
6. หน้ารายละเอียด:
   - "[TEST] จ่ายบางส่วน": คงเหลือ 74,750.25 จากยอดรวม 120,000.50, รายการเงินเข้า 2 รายการ → เลือก ก.ย. 2569 เหลือ โอน 30,000.00
     → ต.ค. 2569 เหลือ เช็ค 15,250.25 · ประวัติ "ยังไม่มีการแก้ไข"
   - "[TEST] มีประวัติการแก้ไข": คงเหลือ 40,500.00 จาก 52,500.00, เงินเข้าแค่ เช็ค 12,000.00 (3,000 ที่ยกเลิกไม่แสดง)
     ประวัติ 4 รายการ ใหม่ → เก่า โดยชื่อ sales: ยกเลิกรายการจ่าย (โอน · 3,000.00) → แก้ไขรายการจ่าย (ยอด 10,000.00 → 12,000.00,
     วิธีจ่าย โอน → เช็ค) → แก้ไขยอดค้าง (วันเครดิต 30 → 45) → แก้ไขยอดค้าง (ยอดรวม 50,000.00 → 52,500.00, วันครบกำหนดจริง +1 วัน)
     ต้องไม่มีรายการที่ไม่มีช่องเปลี่ยน · **ถ้าลำดับไม่ตรงนี้ แจ้งด้วย** (SQL Editor อาจรวมทั้งไฟล์เป็น transaction เดียว)
   - รีเฟรชที่ `/r/<id>` ได้ (ไม่ 404), "← กลับไปตาราง" แล้วตัวกรองเดิมยังอยู่, `/r/abc` → "ไม่พบยอดค้างนี้"
7. ENG ↔ ไทย: ทุกป้ายเปลี่ยน วันที่เป็น "6 Oct 2026" / "6 ต.ค. 2569"
8. role ผิด / ไม่มีสิทธิ์ (หน้าจอ M3 เป็นการดูอย่างเดียว ทั้ง 2 role ดูได้ตามตาราง prd ข้อ 9):
   - ทั้ง owner และ sales ไม่มีปุ่มเพิ่ม/แก้ไขใด ๆ (มาใน M4)
   - ออกจากระบบแล้วเปิด `/r/<id>` ตรง ๆ → ถูกพาไปหน้า login
   - แท็บที่ไม่ได้ล็อกอิน: console `fetch('<VITE_SUPABASE_URL>/rest/v1/receivable_summary?select=id', {headers:{apikey:'<publishable key>'}}).then(r=>r.json()).then(console.log)` → `[]` หรือ permission denied
9. มือถือ: การ์ด 1 คอลัมน์, ตัวกรองไม่ล้นจอ, dialog ปิดได้, ไม่มี error ใน console ทั้ง 2 เบราว์เซอร์

**ก่อนส่งให้ลูกค้า (หลังทดสอบเสร็จเท่านั้น)**
10. แก้ `sales_email` ใน `cleanup_test_data.sql` แล้วรัน → 0 / 0 / 0 → รีเฟรชแอป: ไม่มีการ์ด, ยอดรวม 0.00, "ไม่มียอดค้างที่ครบกำหนดในเดือนที่เลือก"

### ต่างจาก ui-reference / สิ่งที่ยังไม่แน่ใจ
- ui-reference ไม่มีส่วนประวัติการแก้ไข (เดโมเก็บ audit ไว้เบื้องหลัง) — ออกแบบใหม่ด้วย style `.panel-box` / `.txns` เดิม
  อยู่ใต้ 2 กล่องบน คอมกว้างเต็มแถว
- ยังไม่มีปุ่ม JPG / PDF (M7), "เพิ่มยอดค้าง" / "รายชื่อบริษัท" และข้อความ "กด เพิ่มยอดค้าง…" ในหน้าว่าง (M4)
- "ข้อมูล ณ" ไม่ขยับเมื่อ**ยกเลิกการ์ด** (การ์ดที่ยกเลิกไม่อยู่ใน view) — ต้องตัดสินใจใน M4: ใช้ `max(audit_logs.created_at)` แทนไหม
- การ์ดที่ยกเลิกแล้วเปิดหน้ารายละเอียดไม่ได้ จึงไม่เห็นรายการ "ยกเลิกการ์ด" ในประวัติ (schema 3.5 ให้แสดง แต่ view ไม่มีการ์ดที่ยกเลิก)
- เดือนเริ่มต้นของตัวกรองใช้นาฬิกาเครื่องผู้ใช้ (เวลาไทย) — ใช้แค่เลือกค่าเริ่มต้น ค่าคำนวณทั้งหมดยังใช้วันนี้จาก database
- หลังรัน cleanup "ข้อมูล ณ" จะเป็นเวลาที่รัน cleanup (การจ่าย `[TEST]` ที่ยกเลิกยังอ่านได้)

### Migrations ที่รันแล้ว
- [x] `003_summary_paid_late.sql` — รันบน Supabase แล้ว (2026-10-06)
- [x] `test_data.sql` รันแล้ว — ข้อมูล `[TEST]` ยังอยู่ ต้องรัน `cleanup_test_data.sql` ก่อนส่งให้ลูกค้า (ข้อ 10)

### ผลทดสอบ (Definition of done)
- [x] บน Supabase จริง: `m2_checks` 39/39, `m3_checks` 5/5
- [x] owner + sales ในคนละเบราว์เซอร์เห็นตัวเลขตรงกัน: ต.ค. 174,150.25 · 4 รายการ, ค้างข้ามเดือนบนสุดทุกเดือน,
      ตัวกรองทุกแบบ, สรุปผล, รายการเงินเข้ากรองเดือน, ประวัติ 4 รายการ, ENG/ไทย ถูก (ข้อ 4–7)
- [x] ข้อ 8: ไม่มีปุ่มแก้ไขทั้ง owner และ sales
- [x] ข้อ 8: ออกจากระบบแล้วเปิด `/r/<id>` ตรง ๆ → ถูกพาไปหน้า login
- [x] ข้อ 8: เรียก `receivable_summary` โดยไม่ล็อกอิน → 401 (สิทธิ์ถูก revoke จาก anon; key ถูกต้อง ยืนยันจาก `/auth/v1/health`)
- [x] ข้อ 9: เปิดบนมือถือผ่าน Vercel ได้, ไม่มี error ใน console หลังล็อกอิน
- [x] `npm run build`, `npm run lint` ผ่าน
- [x] ไม่มี secret ใน repo (อีเมลใน seed / test เป็น placeholder)
- [x] docs อัปเดต (schema.md 4, architecture.md 9 + 11, implementation-plan.md V0.1)
- [x] commit
