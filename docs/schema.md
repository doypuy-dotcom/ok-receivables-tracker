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
- ตารางหลักมี `created_at`, `created_by`, `updated_at`, `updated_by`

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
| name | text | not null, **unique** | ชื่อบริษัท |
| is_active | boolean | not null, default true | ซ่อนจากรายการเลือก |
| created_at / created_by / updated_at / updated_by | | | |

- สาขา หรือบริษัทที่มีหลายใบวางบิลในบัญชีเดือนเดียวกัน → ใช้ชื่อแยกกัน เช่น `บ.X 1`, `บ.X 2`
- ชื่อที่พิมพ์ใหม่ในฟอร์มเพิ่ม/แก้ไขยอดค้าง จะถูกสร้างเป็นบริษัทใหม่อัตโนมัติ

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
| receivable_id | uuid | not null, FK → `receivables(id)` | เป็นของการ์ดไหน |
| amount | numeric(14,2) | not null, > 0 | ยอดเงิน |
| method | payment_method | not null | โอน / เช็ค |
| paid_date | date | not null | โอน = วันที่เงินเข้า, เช็ค = วันที่เช็คขึ้นเงิน |
| paid_time | time | not null | เวลา |
| is_cancelled | boolean | not null, default false | ยกเลิกแล้ว |
| created_at / created_by / updated_at / updated_by | | | |

- **ผลรวมการจ่ายที่ไม่ถูกยกเลิก ต้องไม่เกิน `total_amount`** ของการ์ด ตรวจทั้งในแอปและใน database (trigger) เพราะคนอาจเรียก API ตรงโดยไม่ผ่านแอป
- เพิ่มการจ่ายในการ์ดที่ถูกยกเลิกไม่ได้

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

| ค่า | สูตร |
|---|---|
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

## 6. ยังไม่ได้ออกแบบ

- **ตาราง feedback** — รอกำหนดระบบเก็บ feedback (prd ข้อ 11)
