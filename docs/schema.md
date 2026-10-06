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

## 5. สิทธิ์ (RLS) โดยสรุป

| ตาราง | เจ้าของ | ฝ่ายขาย |
|---|---|---|
| profiles | อ่านได้ทุกคน | อ่านได้ทุกคน |
| companies | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| receivables | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| payments | อ่าน | อ่าน, เพิ่ม, แก้ไข |
| audit_logs | อ่าน | อ่าน |

- ไม่มีใคร DELETE ได้
- ผู้ใช้ที่ `is_active = false` ทำอะไรไม่ได้เลย
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

## 7. ยังไม่ได้ออกแบบ

- **ตาราง feedback** — รอกำหนดระบบเก็บ feedback (prd ข้อ 11)
