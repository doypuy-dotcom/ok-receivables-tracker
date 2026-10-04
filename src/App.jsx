import { useEffect, useState } from 'react'
import { checkSupabaseHealth, isConfigured, supabaseUrl } from './lib/supabase.js'

const LABEL = {
  checking: 'กำลังตรวจสอบการเชื่อมต่อ…',
  ok: 'เชื่อมต่อ Supabase ได้',
  fail: 'เชื่อมต่อ Supabase ไม่ได้',
}

export default function App() {
  const [health, setHealth] = useState({ state: 'checking', detail: '' })

  useEffect(() => {
    let alive = true
    checkSupabaseHealth().then(({ ok, detail }) => {
      if (alive) setHealth({ state: ok ? 'ok' : 'fail', detail })
    })
    return () => {
      alive = false
    }
  }, [])

  const cls = health.state === 'ok' ? 'ok' : health.state === 'fail' ? 'fail' : 'wait'

  return (
    <>
      <header className="topbar">
        <div className="topbar-in">
          <div className="brand">
            <div className="logo">OK</div>
            <div className="brand-name">
              โอ เค เอ็นจิเนียริ่ง ไฮเท็ค
              <small>บริษัท โอ เค เอ็นจิเนียริ่ง ไฮเท็ค จำกัด</small>
            </div>
          </div>
        </div>
      </header>

      <main>
        <h1 className="page-title">ระบบติดตามยอดค้างชำระ</h1>
        <p className="page-sub">M0 — scaffold และตรวจการเชื่อมต่อ Supabase</p>

        <section className="card">
          <h2>สถานะการเชื่อมต่อ</h2>
          <p className={`status ${cls}`}>
            <span className="dot" />
            {LABEL[health.state]}
          </p>
          {health.detail && <p className="detail">{health.detail}</p>}
          {isConfigured && <p className="detail">{supabaseUrl}</p>}

          {!isConfigured && (
            <p className="hint">
              คัดลอก <code>.env.example</code> เป็น <code>.env.local</code> แล้วใส่ค่า{' '}
              <code>VITE_SUPABASE_URL</code> และ <code>VITE_SUPABASE_PUBLISHABLE_KEY</code> จากนั้น
              รีสตาร์ท dev server
            </p>
          )}
        </section>
      </main>
    </>
  )
}
