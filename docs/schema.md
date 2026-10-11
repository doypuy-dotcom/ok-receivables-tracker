# schema.md — ระบบติดตามยอดค้างชำระ

> Database: Supabase (PostgreSQL) · อ้างอิง: docs/prd.md
> **ล็อก schema นี้ก่อนเขียนโค้ด** ห้ามเปลี่ยนชื่อหรือเพิ่มช่องโดยไม่แก้ไฟล์นี้ใน commit เดียวกัน

---

## 1. หลักทั่วไป

- Primary key ทุกตาราง: `uuid` default `gen_random_uuid()`
- เวลา: `timestamptz` · วันที่ไม่มีเวลา: `date` · เงิน: `numeric(14,2)` (ห้ามใช้ float)
- **"วันนี้"** ของระบบ = วันที่ตามเวลาไทย: `(now() at time zone 'Asia/Bangkok')::date`
  (ถ้าใช้ `current_date` เฉย ๆ จะเป็นเวลา UTC ช่วง 00:00–07:00 น. วันจะเพี้ยนไป 1 วัน)
- **ห้าม DELETE** ตารางหลัก ใช้ `is_cancelled` หรือ `is_active` แทน
- **เปิด RLS ทุกตาราง** (เปิด automatic RLS ไว้ในโปรเจกต์แล้ว) และเขียน policy พร้อมตาราง
- ตารางหลักมี `created_at`, `created_by`, `updated_at`, `updated_by` — ทั้ง 4 ช่อง **not null**
  - `created_at` / `updated_at`: `timestamptz` default `now()`
  - `created_by` / `updated_by`: `uuid` FK → `profiles(id)`
  - trigger ใส่ให้อัตโนมัติจาก `auth.uid()` ทุก insert/update (ตอนสร้าง `updated_*` = `created_*`)
    ค่าที่ส่งมาจากแอปถูกเขียนทับ และตอนแก้ไข `id`, `created_at`, `created_by` คงค่าเดิมเสมอ
  - **ไม่มีผู้ใช้ล็อกอิน (`auth.uid()` ว่าง) → เขียนไม่ได้** รวมถึงรันใน SQL Editor
    ต้องตั้ง `request.jwt.claims` เป็นผู้ใช้จริงก่อน (เพราะ `audit_logs.user_id` ห้ามว่าง)
- **ตารางแบบต่อท้ายอย่างเดียว (append-only)** — `audit_logs`, `receivable_notes`, `app_feedback` —
  **ไม่มี `updated_at` / `updated_by`** เพราะแก้ไม่ได้เลย (ไม่มี policy UPDATE / DELETE ให้ใคร)
  มีแค่ `created_at` + คนที่เขียน (`user_id` / `created_by`) ซึ่ง trigger ใส่ให้จาก `auth.uid()`
  ตารางหลักที่แก้ได้ (`companies`, `receivables`, `payments`) ยังมีทั้ง 4 ช่องตามเดิม

## 2. Enums

```sql
create type user_role      as enum ('owner', 'sales');
create type payment_method as enum ('transfer', 'cheque');
create type audit_action   as enum ('create', 'update', 'cancel');
```

## 3. ตาราง

### 3.1 `profiles` — ผู้ใช้

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK, FK → `auth.users(id)` | ผูกกับบัญชีล็อกอินของ Supabase |
| display_name | text | not null | ชื่อที่แสดงมุมขวาบน |
| role | user_role | not null | `owner` = เจ้าของ, `sales` = ฝ่ายขาย |
| is_active | boolean | not null, default true | ปิดบัญชีโดยไม่ลบ |
| created_at | timestamptz | default now() | |

- อีเมลและรหัสผ่านเก็บใน `auth.users` ของ Supabase ไม่เก็บซ้ำที่นี่
- **ผู้ใช้แก้ role ของตัวเองไม่ได้** สร้างและกำหนด role จาก Supabase dashboard เท่านั้น
- **ข้อตกลงชื่อบัญชีทดสอบ: `display_name` ของบัญชีทดสอบทุกบัญชีต้องมีคำว่า "ทดสอบ"**
  (เหมือนที่บริษัททดสอบใช้ชื่อขึ้นต้นด้วย `[TEST]`) เพราะรายงานผลวัดทุกคำสั่งใน
  `supabase/queries/feedback_report.sql` ตัดข้อมูลทดสอบออกด้วยเงื่อนไขนี้
  **และนี่เป็นทางเดียวที่ตัดได้ ไม่ใช่การลบทีหลัง** — `app_feedback` และ `receivable_notes`
  เป็น append-only (ข้อ 3.6) ลบและแก้ไม่ได้เลย ถ้าทดลองส่งความคิดเห็นด้วยบัญชีที่ไม่มีคำนี้
  คำตอบจะปนกับของลูกค้าจริงและดึงค่าเฉลี่ยของเวอร์ชันนั้นเพี้ยนไปตลอด

### 3.2 `companies` — รายชื่อบริษัท

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| name | text | not null, **unique**, ห้ามว่าง/มีแต่ช่องว่าง/มีช่องว่างหน้าหรือหลัง | ชื่อบริษัท |
| is_active | boolean | not null, default true | ซ่อนจากรายการเลือก |
| created_at / created_by / updated_at / updated_by | | | |

- กฎชื่อ: `constraint companies_name_trimmed check (name = btrim(name) and name <> '')`
  แอปควร trim ก่อนส่ง (ชื่อซ้ำเช็คแบบตรงตัวอักษร)
- สาขา หรือบริษัทที่มีหลายใบวางบิลในบัญชีเดือนเดียวกัน → ใช้ชื่อแยกกัน เช่น `บ.X 1`, `บ.X 2`
- ชื่อที่พิมพ์ใหม่ในฟอร์มเพิ่ม/แก้ไขยอดค้าง จะถูกสร้างเป็นบริษัทใหม่อัตโนมัติ
  (แอป trim ก่อนเทียบและก่อนส่ง) ถ้าชื่อตรงกับบริษัทที่ `is_active = false` อยู่ (เช่นหลัง cleanup ข้อมูล `[TEST]`)
  จะใช้บริษัทเดิมและตั้ง `is_active = true` คืน ไม่สร้างชื่อซ้ำ (name เป็น unique)
- รายการให้เลือกและกล่อง "รายชื่อบริษัท" แสดงเฉพาะบริษัทที่ `is_active = true`

### 3.3 `receivables` — การ์ดยอดค้าง

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| company_id | uuid | not null, FK → `companies(id)` | เป็นของบริษัทไหน |
| account_month | date | not null, ต้องเป็นวันที่ 1 ของเดือน | บัญชีเดือน (เดือนที่ลูกค้าซื้อของ) |
| total_amount | numeric(14,2) | not null, > 0 | ยอดรวม (บาท) |
| credit_days | integer | not null, > 0 | จำนวนวันเครดิต |
| credit_start_date | date | not null | วันเริ่มนับเครดิต |
| actual_start_date | date | not null | วันเริ่มนับวันจริง |
| actual_due_date | date | not null, >= actual_start_date | วันครบกำหนดจริง |
| is_cancelled | boolean | not null, default false | ยกเลิกแล้ว |
| created_at / created_by / updated_at / updated_by | | | |

- **1 บริษัท + 1 บัญชีเดือน = การ์ดได้ 1 ใบ** (นับเฉพาะการ์ดที่ไม่ถูกยกเลิก):
  ```sql
  create unique index receivables_one_per_company_month
    on receivables (company_id, account_month) where not is_cancelled;
  ```
- เปลี่ยนบริษัทของการ์ด (เลือกผิด / พิมพ์ชื่อผิด) ทำผ่านปุ่ม "แก้ไขยอดค้าง" โดยแก้ `company_id`

### 3.4 `payments` — การจ่าย

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| receivable_id | uuid | not null, FK → `receivables(id)`, **เปลี่ยนไม่ได้หลังสร้าง** | เป็นของการ์ดไหน |
| amount | numeric(14,2) | not null, > 0 | ยอดเงิน |
| method | payment_method | not null | โอน / เช็ค |
| paid_date | date | not null | โอน = วันที่เงินเข้า, เช็ค = วันที่เช็คขึ้นเงิน |
| paid_time | time | not null | เวลา |
| is_cancelled | boolean | not null, default false | ยกเลิกแล้ว |
| created_at / created_by / updated_at / updated_by | | | |

- **ผลรวมการจ่ายที่ไม่ถูกยกเลิก ต้องไม่เกิน `total_amount`** ของการ์ด ตรวจทั้งในแอปและใน database (trigger) เพราะคนอาจเรียก API ตรงโดยไม่ผ่านแอป
  ตอนแก้ไขการจ่าย ไม่นับยอดเดิมของการจ่ายนั้นเอง และแก้ `total_amount` ให้ต่ำกว่ายอดที่จ่ายแล้วไม่ได้
- เพิ่มการจ่ายในการ์ดที่ถูกยกเลิกไม่ได้ (insert หรือเลิกยกเลิกการจ่ายในการ์ดนั้น)
  การจ่ายเดิมในการ์ดนั้นยังแก้ / ยกเลิกได้ และยกเลิกการ์ดไม่ได้ยกเลิกการจ่ายตาม
- **ย้ายการจ่ายไปการ์ดอื่นไม่ได้** ใส่ผิดการ์ด → ยกเลิกการจ่ายนั้นแล้วสร้างใหม่ในการ์ดที่ถูกต้อง
  (ประวัติของทั้ง 2 การ์ดจึงครบ)

### 3.5 `audit_logs` — ประวัติการแก้ไข

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| user_id | uuid | not null, FK → `profiles(id)` | ใครทำ |
| action | audit_action | not null | สร้าง / แก้ไข / ยกเลิก |
| table_name | text | not null, ∈ (`companies`, `receivables`, `payments`) | ทำกับตารางไหน |
| record_id | uuid | not null | ทำกับรายการไหน |
| receivable_id | uuid | null, FK → `receivables(id)` | **การ์ดที่เกี่ยวข้อง** (ใช้แสดงในหน้ารายละเอียด) |
| old_value | jsonb | null | ข้อมูลก่อนทำ (ว่างถ้าเป็นการสร้าง) |
| new_value | jsonb | not null | ข้อมูลหลังทำ |
| created_at | timestamptz | not null, default now() | ทำเมื่อไหร่ |

- `receivable_id`: แถวของ `receivables` = id ของการ์ดนั้น, แถวของ `payments` = การ์ดที่การจ่ายนั้นอยู่, แถวของ `companies` = ว่าง
- **เขียนโดย database trigger เท่านั้น** ทุก insert/update บน 3 ตารางหลัก แอปไม่ต้องเขียนเอง จึงลืมไม่ได้
- **ห้ามแก้ไข ห้ามลบ** ไม่มี policy UPDATE/DELETE สำหรับใครเลย
- การเปลี่ยน `is_cancelled` เป็น true บันทึกเป็น action `cancel`

**สิ่งที่แสดงในหน้ารายละเอียดการ์ด** (ส่วน "ประวัติการแก้ไข"):

| แสดง | ไม่แสดง |
|---|---|
| แก้ไขการ์ด (`receivables` + `update`) | สร้างการ์ด |
| ยกเลิกการ์ด | เพิ่มการจ่าย (มีในรายการเงินเข้าแล้ว) |
| แก้ไขการจ่าย (`payments` + `update`) | |
| ยกเลิกการจ่าย (`payments` + `cancel`) | |

แต่ละรายการแสดง: ใครแก้, เมื่อไหร่, ช่องที่เปลี่ยน จากค่าเดิม → ค่าใหม่

### 3.6 `receivable_notes` — หมายเหตุบนการ์ด (เพิ่มใน 005)

> prd.md ข้อ 5 รายการที่ 11 และตารางสิทธิ์ ข้อ 9 · ที่มา: feedback รอบ 1 ข้อ 4 + รอบ 0 ข้อ 3b/4

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| receivable_id | uuid | not null, FK → `receivables(id)` | หมายเหตุของการ์ดไหน |
| body | text | not null, ห้ามว่าง/มีแต่ช่องว่าง/มีช่องว่างหน้าหรือหลัง, ยาวไม่เกิน **1,000 ตัวอักษร** | ข้อความ |
| created_by | uuid | not null, FK → `profiles(id)` | ใครเขียน (trigger ใส่จาก `auth.uid()`) |
| created_at | timestamptz | not null, default now() | เขียนเมื่อไหร่ (trigger ใส่) |

- **ผูกกับการ์ด ไม่ใช่กับบริษัท** (ตัดสินใจกับลูกค้า 12 ต.ค.): เรื่องที่จดเป็นเรื่องของยอดค้างใบนั้น
  เช่น "ขอเลื่อนจ่ายไป 25" หรือ "โอนมา 9,970 ขาด 30 เพราะค่าธรรมเนียมธนาคาร"
  บริษัทเดียวกันในอีกบัญชีเดือนจึงมีหมายเหตุของตัวเองแยกกัน
- กฎข้อความ: `constraint receivable_notes_body_trimmed check (body = btrim(body) and body <> '')`
  และ `receivable_notes_body_len check (length(body) <= 1000)` — แอป trim ก่อนส่ง
- **เขียนหมายเหตุในการ์ดที่ถูกยกเลิกไม่ได้** (trigger `check_note_rules` → `note_receivable_cancelled`)
  เหมือนกฎของการจ่าย (ข้อ 3.4) หมายเหตุเดิมของการ์ดนั้นยังอ่านได้ตามปกติ
- **เปลี่ยน `receivable_id` ไม่ได้ เพราะแก้แถวไม่ได้เลย** (ไม่มี policy UPDATE)
- เปิด Realtime ให้ตารางนี้ด้วย (ดู architecture.md ข้อ 7): ฝ่ายขายเขียนบนคอม → เจ้าของเห็นบนมือถือทันที

**ข้อยกเว้น: ไม่มี `audit_logs` และไม่มี `is_cancelled`**

ตารางนี้เป็นข้อยกเว้นเดียวของกฎ "ทุกการเพิ่ม/แก้ไข/ยกเลิกบันทึกลง `audit_logs`" (prd.md ข้อ 9)
เพราะ **ไม่มี policy UPDATE และ DELETE ให้ใครเลย** จึงมีการกระทำได้แบบเดียวคือ "เขียนรายการใหม่"
แถวที่เขียนแล้วเปลี่ยนไม่ได้อีก → **ตัวตารางเองเป็นประวัติในตัวแล้ว** `audit_logs` จะได้แค่แถว
`create` ที่ซ้ำกับแถวจริงทุกตัวอักษร ไม่เพิ่มข้อมูลอะไรเลย

- **เขียนผิดแก้ไม่ได้ ให้เขียนรายการใหม่** (เช่น "แก้จากข้อความก่อนหน้า: นัดวันที่ 25 ไม่ใช่ 15")
  ทั้ง 2 รายการยังอยู่ ใครอ่านย้อนก็เห็นว่าเข้าใจผิดตอนไหนและแก้เมื่อไหร่
- ไม่มี `is_cancelled` ด้วยเหตุผลเดียวกัน: ยกเลิกได้ = ต้องมี UPDATE = ต้องมี `audit_logs`
  และทำให้ซ่อนสิ่งที่เคยรายงานเจ้าของไปแล้วได้ ซึ่งขัดกับจุดประสงค์ของหมายเหตุ
  (กฎ "ห้าม DELETE ใช้ `is_cancelled` แทน" ยังอยู่ครบ — ตารางนี้ไม่มี DELETE เหมือนกัน)
- กฎเดียวกันนี้ใช้กับ `app_feedback` (ข้อ 3.7) ด้วย

### 3.7 `app_feedback` — ความคิดเห็นเกี่ยวกับแอป (เพิ่มใน 005)

> prd.md ข้อ 11 (เงื่อนไขอาจารย์: ประเมินแต่ละเวอร์ชัน) · แบบ append-only เหมือนข้อ 3.6

| ช่อง | ชนิด | กฎ | ความหมาย |
|---|---|---|---|
| id | uuid | PK | |
| user_id | uuid | not null, FK → `profiles(id)` | ใครส่ง (trigger ใส่จาก `auth.uid()`) |
| role | user_role | not null | role ตอนส่ง (trigger ใส่จาก `my_role()`) |
| app_version | text | not null, ห้ามว่าง, ยาวไม่เกิน 20 | เวอร์ชันที่กำลังใช้ (แอปส่งจาก `src/lib/version.js`) |
| helpful | smallint | not null, 1–5 | ข้อ 1: แอปช่วยงานได้แค่ไหน (ทุกคน) |
| issues | text | null, trim แล้วไม่ว่าง, ยาวไม่เกิน 2,000 | ข้อ 2: อะไรติดขัด/อยากให้เพิ่ม (ทุกคน, ข้ามได้) |
| owner_asks_per_week | integer | 0–200, **not null เมื่อ role = owner และต้องว่างเมื่อเป็น sales** | ข้อ 3: สัปดาห์นี้ต้องถาม/เช็คบัญชีเองกี่ครั้ง |
| sales_sheet_minutes | integer | 0–10000, **not null เมื่อ role = sales และต้องว่างเมื่อเป็น owner** | ข้อ 4: **เดือนนี้**ทำตารางสรุปแบบเดิมให้เจ้าของไปกี่นาที — หน่วย **นาที/เดือน** (0 = ไม่ต้องทำแล้ว) |
| created_at | timestamptz | not null, default now() | ส่งเมื่อไหร่ (trigger ใส่) |

- `user_id`, `role`, `created_at` **แอปส่งมาไม่ได้** trigger เขียนทับทุกครั้ง (เหมือน `created_by` ของตารางหลัก)
  `app_version` มาจากแอป เพราะ database ไม่รู้ว่าเครื่องนั้นโหลดโค้ดเวอร์ชันไหนไว้
- คำถามของแต่ละ role บังคับที่ database ด้วย 2 constraint:
  `app_feedback_owner_question check ((role = 'owner') = (owner_asks_per_week is not null))` และ
  `app_feedback_sales_question check ((role = 'sales') = (sales_sheet_minutes is not null))`
  → ส่งคำตอบของ role อื่นมาด้วยไม่ได้ และข้ามคำถามของ role ตัวเองไม่ได้
- ข้อ 4 รวม "ยังต้องทำไหม" กับ "กี่นาที" เป็นตัวเลขเดียว: **0 = ไม่ต้องทำแล้ว** (prd.md ข้อ 11)
  และถามเป็น **รายเดือน** (ไม่ใช่รายสัปดาห์) เพราะงานนี้ทำเดือนละครั้งตอนสิ้นเดือน
  หน่วยจึงตรงกับ baseline 30 นาที/เดือน ได้ตรง ๆ ไม่ต้องแปลง
- **สิทธิ์:** ทุกคนส่งได้ และ **อ่านได้แค่แถวของตัวเอง** (`user_id = auth.uid()`)
  ไม่มี policy UPDATE / DELETE ให้ใคร · ผู้พัฒนาอ่านทั้งหมดจาก SQL Editor
  (`supabase/queries/feedback_report.sql` สรุปแยกตาม `app_version` × `role` เทียบ baseline ของ prd.md ข้อ 12)
- **ไม่มี `audit_logs`** ด้วยเหตุผลเดียวกับข้อ 3.6 และ**ไม่เปิด Realtime** (ไม่มีหน้าจอไหนต้องอัปเดตตาม)

## 4. ค่าที่คำนวณ (ไม่เก็บในตาราง)

คำนวณใหม่ทุกครั้งที่อ่าน ผ่าน view `receivable_summary` (เฉพาะการ์ดที่ไม่ถูกยกเลิก) เพื่อให้แก้ข้อมูลแล้วทุกอย่างอัปเดตตามเสมอ

- view ตั้ง `security_invoker = true` (ใช้ RLS ของคนที่อ่าน)
- คอลัมน์: ทุกช่องของ `receivables` ยกเว้น `is_cancelled` + `company_name` (= `companies.name`) + ค่าในตารางด้านล่าง
- **% ทั้งหมด** (`actual_pct`, `credit_pct`, `money_pct`) เป็นเลข 0–100 ชนิด `numeric(5,2)`
  **ตัดทศนิยมทิ้ง** เหลือ 2 ตำแหน่ง (`trunc` ไม่ปัด) เพื่อไม่ให้จ่าย 9,999.99 จาก 10,000 แสดงเป็น 100%
- `actual_pct` เมื่อ `actual_due_date = actual_start_date`: ถึงวันนั้นแล้ว = 100 ยังไม่ถึง = 0
- `due_month` = วันที่ 1 ของเดือน (`date`), `paid_in_full_date` ว่างถ้ายังจ่ายไม่ครบ

| ค่า | สูตร |
|---|---|
| company_name | `companies.name` ของการ์ด |
| credit_due_date | `credit_start_date + credit_days` |
| paid_amount | ผลรวม `payments.amount` ที่ไม่ถูกยกเลิก (ไม่มี = 0) |
| balance | `total_amount − paid_amount` |
| is_paid | `balance = 0` |
| paid_in_full_date | `paid_date` ล่าสุด เมื่อ `is_paid` |
| due_month | เดือนของ `actual_due_date` (ใช้กรองตามเดือน) |
| is_carried_over | `not is_paid` และ `due_month` < เดือนของวันนี้ |
| days_to_actual_due | `actual_due_date − วันนี้` (ติดลบ = เลยกำหนด) |
| days_to_credit_due | `credit_due_date − วันนี้` |
| actual_pct | `(วันนี้ − actual_start_date) ÷ (actual_due_date − actual_start_date)` จำกัด 0–100% |
| credit_pct | `(วันนี้ − credit_start_date) ÷ credit_days` จำกัด 0–100% |
| money_pct | `paid_amount ÷ total_amount` |
| paid_late_actual_days | `paid_in_full_date − actual_due_date` (ว่างถ้ายังจ่ายไม่ครบ, > 0 = จ่ายช้ากี่วัน, ≤ 0 = ตรงเวลา) — เพิ่มใน 003 |
| paid_late_credit_days | `paid_in_full_date − credit_due_date` (กฎเดียวกัน) — เพิ่มใน 003 |

- กล่องยอดรวมในหน้าตาราง = ผลรวม `balance` ของการ์ดที่แสดง แอปบวกจาก `balance::text` ด้วยจำนวนเต็มหน่วยสตางค์ (BigInt) ไม่ใช้ float

### 4.1 view `receivable_latest_note` (เพิ่มใน 005)

หมายเหตุล่าสุด **1 แถวต่อ 1 การ์ด** สำหรับการ์ดในหน้าตาราง (prd.md ข้อ 5 รายการที่ 11)
`security_invoker = true` เหมือน `receivable_summary` · คอลัมน์: `receivable_id`, `note_id`,
`body`, `created_by`, `created_at`

- "ล่าสุด" = `created_at` มากสุด (เท่ากันก็ตัดด้วย `id` ให้ผลคงที่) ทำด้วย `distinct on` ใน database
  ไม่ใช่ให้แอปโหลดหมายเหตุทุกแถวของทุกการ์ดมาเรียงเอง
- การ์ดที่ยังไม่มีหมายเหตุไม่มีแถวใน view นี้ (แอปแสดงการ์ดนั้นโดยไม่มีบรรทัดหมายเหตุ)
- หน้ารายละเอียดไม่ได้ใช้ view นี้ อ่าน `receivable_notes` ของการ์ดนั้นทุกแถวตรง ๆ

### 4.2 ตัวชี้วัด "ความสดของข้อมูล" — คำนวณจาก `payments` ที่มีอยู่แล้ว

เงินเข้าแล้วกี่วันเจ้าของถึงเห็นในระบบ (prd.md ข้อ 12 — จุดแข็งหลักของแอป)
**ไม่ต้องเพิ่มตาราง ไม่ต้องเพิ่มช่อง ไม่ต้องมี migration** เพราะข้อมูลครบอยู่แล้ว:

```
ความสด (วัน) = (payments.created_at at time zone 'Asia/Bangkok')::date − payments.paid_date
```

- `created_at` = เวลาที่ฝ่ายขายกดบันทึก (trigger ใส่ให้ แอปเปลี่ยนไม่ได้ — ข้อ 1)
  `paid_date` = วันที่เงินเข้าจริง (โอน = วันเงินเข้า, เช็ค = วันเช็คขึ้นเงิน — ข้อ 3.4)
- ไม่นับการจ่ายที่ `is_cancelled`, ไม่นับบริษัทที่ชื่อขึ้นต้นด้วย `[TEST]`
  และ**ไม่นับการจ่ายที่บันทึกโดยบัญชีทดสอบ** (`created_by` → `display_name` มีคำว่า "ทดสอบ" — ข้อ 3.1)
  กรองทั้ง 2 ทาง เพราะทดสอบด้วยบัญชีทดสอบบนการ์ดจริงก็ทำได้ ตัดทางเดียวไม่พอ
- **นับเฉพาะ `paid_date` ตั้งแต่ 9 ต.ค. 2569 (วันส่งมอบ V0.1)** การจ่ายก่อนหน้านั้นคือการกรอก
  ย้อนหลังตอนเริ่มใช้แอป ซึ่งทำให้ตัวเลขสูงเกินจริงและไม่ได้สะท้อนการใช้งานปกติ
- ค่าติดลบ = บันทึกล่วงหน้าก่อนวันเงินเข้า (ได้เช็คแล้วแต่ยังไม่ถึงวันขึ้นเงิน) = กรณีที่ดีที่สุด
  นับรวมตามจริง ไม่ปรับเป็น 0
- คำสั่งที่ 5 ของ `supabase/queries/feedback_report.sql` (จำนวนรายการ / เฉลี่ย / มัธยฐาน / สูงสุด
  แยกตามสัปดาห์ของวันเงินเข้า) — **ไม่ได้ทำเป็น view** เพราะเป็นรายงานของผู้พัฒนา ไม่มีหน้าจอในแอปที่อ่าน

## 5. สิทธิ์ (RLS) โดยสรุป

| ตาราง | เจ้าของ | ฝ่ายขาย |
|---|---|---|
| profiles | อ่านได้ทุกคน | อ่านได้ทุกคน |
| companies | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| receivables | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| payments | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| audit_logs | อ่าน | อ่าน |
| receivable_notes | อ่าน | อ่าน, **เพิ่ม** (แก้ไม่ได้) |
| app_feedback | เพิ่ม, อ่าน**แถวของตัวเอง** | เพิ่ม, อ่าน**แถวของตัวเอง** |

- ไม่มีใคร DELETE ได้
- ผู้ใช้ที่ `is_active = false` ทำอะไรไม่ได้เลย
- **ไม่มีใคร UPDATE `receivable_notes` และ `app_feedback` ได้** (append-only — ข้อ 3.6)
- รายละเอียด policy อยู่ใน AGENTS.md / migration

## 6. Error ที่แอปต้องแปลเป็นภาษาคน

ข้อความ (`message`) หรือชื่อ constraint คงที่ ใช้จับใน M4 ได้ (`details` เป็นภาษาไทยสำหรับดีบัก)

| code | message / constraint | เกิดเมื่อ |
|---|---|---|
| 42501 | `not_authenticated` | เขียนข้อมูลโดยไม่มีผู้ใช้ล็อกอิน |
| 42501 | (RLS) `new row violates row-level security policy` / `permission denied` | role ไม่มีสิทธิ์ (เช่น owner เขียน, ใครก็ตาม DELETE) |
| 23514 | `payments_exceed_total` | ยอดจ่ายรวม (ไม่นับที่ยกเลิก) เกิน `total_amount` |
| 23514 | `total_below_paid` | แก้ `total_amount` ให้ต่ำกว่ายอดที่จ่ายแล้ว |
| 23514 | `receivable_cancelled` | เพิ่มการจ่ายในการ์ดที่ถูกยกเลิก |
| 23514 | `payment_receivable_immutable` | เปลี่ยน `receivable_id` ของการจ่าย |
| 23514 | constraint `companies_name_trimmed` | ชื่อบริษัทว่าง / มีแต่ช่องว่าง / มีช่องว่างหน้าหรือหลัง |
| 23514 | constraint `receivables_*` (`account_month_first_day`, `total_amount_positive`, `credit_days_positive`, `due_after_start`), `payments_amount_positive` | ค่าผิดกฎในตาราง |
| 23505 | constraint `companies_name_key` | ชื่อบริษัทซ้ำ |
| 23505 | constraint `receivables_one_per_company_month` | การ์ดของบริษัทนี้ในเดือนนี้มีอยู่แล้ว |
| 23514 | `note_receivable_cancelled` | เขียนหมายเหตุในการ์ดที่ถูกยกเลิก (ตรวจก่อน `receivable_cancelled` เพราะชื่อซ้อนกัน) |
| 23514 | constraint `receivable_notes_body_trimmed` / `receivable_notes_body_len` | หมายเหตุว่าง / มีช่องว่างหน้า-หลัง / ยาวเกิน 1,000 ตัวอักษร |
| 23514 | constraint `app_feedback_helpful_range` | คะแนนข้อ 1 ไม่อยู่ใน 1–5 |
| 23514 | constraint `app_feedback_owner_question` / `app_feedback_sales_question` | ตอบคำถามของ role อื่น หรือข้ามคำถามของ role ตัวเอง |
| 23514 | constraint `app_feedback_asks_range` / `app_feedback_minutes_range` / `app_feedback_issues_*` / `app_feedback_version_*` | ค่าผิดกฎในตาราง feedback |

## 7. ยังไม่ได้ออกแบบ

- (ว่าง) — ตาราง feedback ออกแบบแล้วในข้อ 3.7 (prd ข้อ 11 ตกลงจบ 12 ต.ค.)
