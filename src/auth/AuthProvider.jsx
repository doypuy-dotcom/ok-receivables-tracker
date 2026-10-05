// session + role ตาม architecture.md ข้อ 4
// มี session → อ่าน profiles ของตัวเอง → ไม่พบ / is_active = false → ออกจากระบบ + แจ้งเตือน
// role ในแอปใช้แค่เลือกว่าจะแสดงอะไร สิทธิ์จริงอยู่ที่ RLS
import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { AuthContext } from './useAuth.js'

export function AuthProvider({ children }) {
  // undefined = กำลังตรวจ session ที่จำไว้ในเครื่อง, null = ไม่ได้ล็อกอิน
  const [session, setSession] = useState(supabase ? undefined : null)
  // ผลการโหลด profile ล่าสุด: { userId, status: 'ready' | 'error', profile }
  const [result, setResult] = useState(null)
  // ข้อความที่จะแสดงในหน้า login หลังถูกบังคับออกจากระบบ (key ของ i18n)
  const [notice, setNotice] = useState(null)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (!supabase) return
    supabase.auth
      .getSession()
      .then(({ data }) => setSession(data.session ?? null))
      .catch(() => setSession(null))
    // ห้ามเรียก supabase ใน callback นี้โดยตรง (supabase-js จะค้าง) — โหลด profile ใน effect ด้านล่างแทน
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s ?? null))
    return () => data.subscription.unsubscribe()
  }, [])

  const userId = session?.user?.id ?? null

  useEffect(() => {
    if (!userId) return
    let alive = true
    supabase
      .from('profiles')
      .select('id, display_name, role, is_active')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (!alive) return
        if (error) {
          setResult({ userId, status: 'error', profile: null })
          return
        }
        // RLS ไม่คืนแถวให้ผู้ใช้ที่ไม่มี profile หรือ is_active = false
        if (!data || !data.is_active) {
          setNotice('eNoAccess')
          supabase.auth.signOut({ scope: 'local' })
          return
        }
        setResult({ userId, status: 'ready', profile: data })
      })
    return () => {
      alive = false
    }
  }, [userId, reloadKey])

  const signIn = useCallback(async (email, password) => {
    setNotice(null)
    return supabase.auth.signInWithPassword({ email, password })
  }, [])

  // scope 'local': ออกเฉพาะเครื่องนี้ ไม่เตะเครื่องอื่นของผู้ใช้คนเดียวกันออก
  const signOut = useCallback(() => supabase.auth.signOut({ scope: 'local' }), [])

  const retryProfile = useCallback(() => {
    setResult(null)
    setReloadKey((k) => k + 1)
  }, [])

  // status: idle (ไม่ได้ล็อกอิน) | loading | ready | error
  const current = userId && result?.userId === userId ? result : null
  const profileStatus = !userId ? 'idle' : (current?.status ?? 'loading')

  const value = {
    session,
    profile: current?.profile ?? null,
    profileStatus,
    notice,
    signIn,
    signOut,
    retryProfile,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
