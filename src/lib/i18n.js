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

    placeholder: 'ตารางยอดค้าง (M3)',
    placeholderSub: 'หน้านี้จะแสดงตารางยอดค้างชำระใน M3',
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

    placeholder: 'Outstanding payments (M3)',
    placeholderSub: 'The receivables list arrives in M3',
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
