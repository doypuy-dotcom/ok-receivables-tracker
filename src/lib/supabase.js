// Supabase client — browser side.
// ใช้ได้เฉพาะ VITE_SUPABASE_URL และ VITE_SUPABASE_PUBLISHABLE_KEY เท่านั้น
// ห้ามนำ service_role key หรือ secret ใด ๆ มาไว้ในไฟล์นี้
import { createClient } from '@supabase/supabase-js'

export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
export const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const isConfigured = Boolean(supabaseUrl && supabasePublishableKey)

export const supabase = isConfigured
  ? createClient(supabaseUrl, supabasePublishableKey)
  : null

/**
 * เรียก Auth health endpoint ของ Supabase เพื่อดูว่าเชื่อมต่อได้หรือไม่
 * คืนค่า { ok, detail } — ยังไม่แตะ database หรือ login ในขั้นนี้
 */
export async function checkSupabaseHealth() {
  if (!isConfigured) {
    return { ok: false, detail: 'ยังไม่ได้ตั้งค่า .env.local' }
  }

  try {
    const res = await fetch(`${supabaseUrl}/auth/v1/health`, {
      headers: { apikey: supabasePublishableKey },
    })

    if (!res.ok) {
      return { ok: false, detail: `HTTP ${res.status} ${res.statusText}`.trim() }
    }

    const body = await res.json().catch(() => null)
    return { ok: true, detail: body?.version ? `GoTrue ${body.version}` : 'auth/v1/health' }
  } catch (err) {
    return { ok: false, detail: err instanceof Error ? err.message : String(err) }
  }
}
