// ข้อความไทย/อังกฤษ — ป้ายตาม docs/ui-reference.html
import { createContext, createElement, useCallback, useContext, useEffect, useState } from 'react'

const T = {
  th: {
    company: 'โอ เค เอ็นจิเนียริ่ง ไฮเท็ค',
    companySub: 'บริษัท โอ เค เอ็นจิเนียริ่ง ไฮเท็ค จำกัด',
    title: 'ตารางยอดค้างชำระ',
    owner: 'เจ้าของบริษัท',
    sales: 'ฝ่ายขาย',
    role: 'ตำแหน่ง: {r}',
    logout: 'ออกจากระบบ',
    loading: 'กำลังโหลด…',
    retry: 'ลองอีกครั้ง',

    loginTitle: 'เข้าสู่ระบบ',
    loginHint: 'ใช้อีเมลและรหัสผ่านที่ได้รับจากผู้ดูแลระบบ',
    email: 'อีเมล',
    password: 'รหัสผ่าน',
    signIn: 'เข้าสู่ระบบ',
    signingIn: 'กำลังเข้าสู่ระบบ…',
    eRequired: 'กรอกอีเมลและรหัสผ่าน',
    eInvalid: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    eNotConfirmed: 'บัญชีนี้ยังไม่ได้ยืนยันอีเมล ติดต่อผู้ดูแลระบบ',
    eRateLimit: 'ลองเข้าสู่ระบบหลายครั้งเกินไป รอสักครู่แล้วลองใหม่',
    eOffline: 'เชื่อมต่ออินเทอร์เน็ตไม่ได้ ตรวจสอบสัญญาณแล้วลองอีกครั้ง',
    eUnknown: 'เข้าสู่ระบบไม่สำเร็จ: {m}',
    eNoAccess: 'บัญชีนี้ยังไม่ได้รับสิทธิ์ใช้งาน หรือถูกปิดใช้งานแล้ว ติดต่อเจ้าของระบบ',
    eProfile: 'โหลดข้อมูลผู้ใช้ไม่ได้ ตรวจสอบสัญญาณอินเทอร์เน็ตแล้วลองอีกครั้ง',
    eLogout: 'ออกจากระบบไม่สำเร็จ ลองอีกครั้ง',
    eNotConfigured: 'ยังไม่ได้ตั้งค่า VITE_SUPABASE_URL และ VITE_SUPABASE_PUBLISHABLE_KEY',

    // ตารางยอดค้าง (ui-reference)
    sub: 'ยอดค้างชำระของแต่ละบริษัท แยกตามเดือนที่ครบกำหนด',
    asOf: 'ข้อมูล ณ {d}',
    monthCap: 'เดือนที่ครบกำหนด',
    allMonths: 'ทุกเดือน',
    unpaidOnly: 'เฉพาะที่ยังค้างชำระ',
    monthsSel: '{n} เดือน',
    dueSel: 'ต้องได้รับในเดือนที่เลือก',
    carryTotal: 'ยอดค้างข้ามเดือน',
    items: '{n} รายการ',
    carryH: 'ยอดค้างข้ามเดือน',
    listH: 'ครบกำหนดในเดือนที่เลือก',
    carryNote: 'ยอดค้างข้ามเดือนของเดือน {m} ค้าง {a} บาท',
    credit: 'เครดิต {n} วัน',
    acct: 'บัญชีเดือน {m}',
    outstanding: 'ยอดค้างชำระ',
    baht: 'บาท',
    viewDetail: 'ดูรายละเอียด',
    status: 'สถานะ',
    actualDue: 'ครบกำหนดจริง {d}',
    creditDue: 'ครบกำหนดเครดิต {d}',
    left: 'เหลืออีก {n} วัน ตาม{k}',
    today: 'ครบกำหนดวันนี้',
    over: 'เลยครบกำหนด {n} วัน จาก{k}',
    kActual: 'วันจริง',
    kCredit: 'วันเครดิต',
    paidOf: 'จ่ายแล้ว {p} จาก {t} บาท',
    remain: 'เหลือ {a} บาท',
    paid: 'จ่ายแล้ว',
    summary: 'สรุปผล',
    paidOn: 'จ่ายครบเมื่อ {d}',
    onTime: 'ตรงเวลา ({k})',
    late: 'ช้ากว่ากำหนด {n} วัน ({k})',
    empty: 'ไม่มียอดค้างที่ครบกำหนดในเดือนที่เลือก',

    // รายละเอียดการ์ด (ui-reference)
    back: 'กลับไปตาราง',
    totalAmt: 'ยอดรวม {a} บาท',
    incoming: 'รายการเงินเข้า',
    all: 'ทั้งหมด',
    transfer: 'โอน',
    cheque: 'เช็ค (ขึ้นเงิน)',
    noPay: 'ยังไม่มีการจ่ายสำหรับยอดนี้',
    noPayMonth: 'ไม่มีรายการเงินเข้าในเดือนนี้',
    info: 'ข้อมูลยอดค้าง',
    fCompany: 'บริษัท',
    fAcct: 'บัญชีเดือน (เดือนที่ลูกค้าซื้อของ)',
    fTotal: 'ยอดรวม (บาท)',
    fCdays: 'จำนวนวันเครดิต',
    fCstart: 'วันเริ่มนับเครดิต',
    fAstart: 'วันเริ่มนับวันจริง',
    fAdue: 'วันครบกำหนดจริง',
    fAmt: 'ยอดเงิน (บาท)',
    fMethod: 'วิธีจ่าย',
    fDateT: 'วันที่เงินเข้า',
    fDateC: 'วันที่เช็คขึ้นเงิน',
    fTime: 'เวลา',
    close: 'ปิด',
    notFound: 'ไม่พบยอดค้างนี้ อาจถูกยกเลิกไปแล้ว',

    // สรุปผล (ui-reference)
    sumH: 'สรุปผล',
    sumPaidOn: 'จ่ายครบวันที่',
    sumCount: 'จำนวนครั้งที่จ่าย',
    sumVsActual: 'เทียบวันครบกำหนดจริง',
    sumVsCredit: 'เทียบวันครบกำหนดเครดิต',
    times: '{n} ครั้ง',

    // ประวัติการแก้ไข (schema.md 3.5 — ไม่มีใน ui-reference)
    historyH: 'ประวัติการแก้ไข',
    noHistory: 'ยังไม่มีการแก้ไข',
    hEditRec: 'แก้ไขยอดค้าง',
    hCancelRec: 'ยกเลิกยอดค้าง',
    hEditPay: 'แก้ไขรายการจ่าย',
    hCancelPay: 'ยกเลิกรายการจ่าย',
    hBy: 'โดย {u}',
    fCancelled: 'สถานะ',
    vCancelled: 'ยกเลิกแล้ว',
    vActive: 'ใช้งาน',
    unknownUser: 'ไม่ทราบชื่อ',

    // error ตอนโหลดข้อมูล
    eLoad: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง',
    ePermission: 'บัญชีนี้ไม่มีสิทธิ์ดูข้อมูลนี้ ติดต่อเจ้าของระบบ',
  },
  en: {
    company: 'O.K. Engineering Hi-Tech',
    companySub: 'O.K. Engineering Hi-Tech Co., Ltd.',
    title: 'Outstanding payments',
    owner: 'Owner',
    sales: 'Sales',
    role: 'Role: {r}',
    logout: 'Sign out',
    loading: 'Loading…',
    retry: 'Try again',

    loginTitle: 'Sign in',
    loginHint: 'Use the email and password you were given',
    email: 'Email',
    password: 'Password',
    signIn: 'Sign in',
    signingIn: 'Signing in…',
    eRequired: 'Enter your email and password',
    eInvalid: 'Wrong email or password',
    eNotConfirmed: 'This account’s email is not confirmed. Contact the administrator',
    eRateLimit: 'Too many sign-in attempts. Wait a moment and try again',
    eOffline: 'No internet connection. Check your signal and try again',
    eUnknown: 'Could not sign in: {m}',
    eNoAccess: 'This account has no access or has been disabled. Contact the owner',
    eProfile: 'Could not load your account. Check your connection and try again',
    eLogout: 'Could not sign out. Try again',
    eNotConfigured: 'VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are not set',

    sub: 'What each company still owes, grouped by due month',
    asOf: 'Data as of {d}',
    monthCap: 'Due month',
    allMonths: 'All months',
    unpaidOnly: 'Unpaid only',
    monthsSel: '{n} months',
    dueSel: 'Due in selected months',
    carryTotal: 'Carried over from earlier months',
    items: '{n} items',
    carryH: 'Carried over',
    listH: 'Due in selected months',
    carryNote: 'Carried over from {m}: {a} THB still unpaid',
    credit: 'Credit {n} days',
    acct: 'Purchase month {m}',
    outstanding: 'Outstanding',
    baht: 'THB',
    viewDetail: 'View details',
    status: 'Status',
    actualDue: 'Expected payment {d}',
    creditDue: 'Credit due {d}',
    left: '{n} days left ({k})',
    today: 'Due today',
    over: '{n} days overdue ({k})',
    kActual: 'expected date',
    kCredit: 'credit terms',
    paidOf: 'Paid {p} of {t} THB',
    remain: '{a} THB left',
    paid: 'Paid',
    summary: 'Summary',
    paidOn: 'Paid in full on {d}',
    onTime: 'On time ({k})',
    late: '{n} days late ({k})',
    empty: 'Nothing is due in the selected months',

    back: 'Back to list',
    totalAmt: 'Total {a} THB',
    incoming: 'Payments received',
    all: 'All',
    transfer: 'Transfer',
    cheque: 'Cheque (cleared)',
    noPay: 'No payments yet for this receivable',
    noPayMonth: 'No payments in this month',
    info: 'Receivable details',
    fCompany: 'Company',
    fAcct: 'Purchase month',
    fTotal: 'Total (THB)',
    fCdays: 'Credit days',
    fCstart: 'Credit start date',
    fAstart: 'Expected-date start',
    fAdue: 'Expected payment date',
    fAmt: 'Amount (THB)',
    fMethod: 'Method',
    fDateT: 'Date received',
    fDateC: 'Cheque cleared date',
    fTime: 'Time',
    close: 'Close',
    notFound: 'This receivable was not found. It may have been cancelled',

    sumH: 'Summary',
    sumPaidOn: 'Paid in full on',
    sumCount: 'Number of payments',
    sumVsActual: 'Against expected date',
    sumVsCredit: 'Against credit due date',
    times: '{n}',

    historyH: 'Edit history',
    noHistory: 'No edits yet',
    hEditRec: 'Receivable edited',
    hCancelRec: 'Receivable cancelled',
    hEditPay: 'Payment edited',
    hCancelPay: 'Payment cancelled',
    hBy: 'by {u}',
    fCancelled: 'Status',
    vCancelled: 'Cancelled',
    vActive: 'Active',
    unknownUser: 'Unknown user',

    eLoad: 'Could not load the data. Try again',
    ePermission: 'This account is not allowed to view this data. Contact the owner',
  },
}

const STORAGE_KEY = 'ok-lang'

function readLang() {
  try {
    const v = localStorage.getItem(STORAGE_KEY)
    return v === 'en' || v === 'th' ? v : 'th'
  } catch {
    return 'th'
  }
}

const LangContext = createContext(null)

export function LangProvider({ children }) {
  const [lang, setLangState] = useState(readLang)

  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])

  const setLang = useCallback((v) => {
    setLangState(v)
    try {
      localStorage.setItem(STORAGE_KEY, v)
    } catch {
      // ไม่มี storage ก็ใช้ภาษาที่เลือกได้จนปิดแท็บ
    }
  }, [])

  const t = useCallback(
    (key, vars = {}) => (T[lang][key] ?? key).replace(/\{(\w+)\}/g, (_, x) => vars[x] ?? ''),
    [lang],
  )

  return createElement(LangContext.Provider, { value: { lang, setLang, t } }, children)
}

export function useLang() {
  return useContext(LangContext)
}
