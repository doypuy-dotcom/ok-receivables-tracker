// กล่อง "ส่งความคิดเห็น" (V1 รอบ ข — prd.md ข้อ 11, schema.md 3.7) เปิดจากเมนูชื่อผู้ใช้มุมขวาบน
// คำถาม 2 ข้อถามทุกคน · ข้อ 3 เฉพาะเจ้าของ · ข้อ 4 เฉพาะฝ่ายขาย (database บังคับด้วย constraint ของ role อีกชั้น)
// user_id / role / created_at ใส่โดย trigger — แอปส่ง app_version จาก src/lib/version.js
// ส่งแล้วแก้ไม่ได้ ลบไม่ได้ และอ่านได้แค่แถวของตัวเอง จึงไม่มีหน้าจออ่าน feedback ในแอป
import { useState } from 'react'
import { useAuth } from '../auth/useAuth.js'
import { FEEDBACK_ISSUES_MAX_LEN, insertFeedback } from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { useDesktopFocus } from '../lib/focus.js'
import { useLang } from '../lib/i18n.js'
import { APP_VERSION } from '../lib/version.js'
import Dialog from './Dialog.jsx'

const SCORES = [1, 2, 3, 4, 5]

// จำนวนเต็ม 0 ขึ้นไป (ช่องตัวเลขของข้อ 3 และ 4)
const isCount = (s) => /^\d{1,7}$/.test(s.trim())

export default function FeedbackDialog({ onClose, onSent }) {
  const { profile } = useAuth()
  const { t } = useLang()
  const [helpful, setHelpful] = useState('')
  const [issues, setIssues] = useState('')
  // ช่องตัวเลขของ role ตัวเองเท่านั้น: owner = จำนวนครั้งที่ต้องถาม/เช็คเอง, sales = นาทีที่ทำตารางสรุป
  const [count, setCount] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const isOwner = profile.role === 'owner'
  const firstRef = useDesktopFocus()

  const submit = async () => {
    if (busy) return
    if (!helpful) {
      setErr(t('eFbHelpful'))
      return
    }
    if (!isCount(count)) {
      setErr(t('eFbNum'))
      return
    }
    const text = issues.trim()
    if (text.length > FEEDBACK_ISSUES_MAX_LEN) {
      setErr(t('eFbIssues', { n: FEEDBACK_ISSUES_MAX_LEN }))
      return
    }
    setBusy(true)
    const n = Number(count.trim())
    const { error } = await insertFeedback({
      app_version: APP_VERSION,
      helpful: Number(helpful),
      // ข้อความว่าง → null (constraint app_feedback_issues_trimmed ไม่ยอมรับข้อความว่าง)
      issues: text || null,
      ...(isOwner ? { owner_asks_per_week: n } : { sales_sheet_minutes: n }),
    })
    setBusy(false)
    if (error) {
      setErr(t(saveErrorKey(error)))
      return
    }
    onSent(t('fbSent'))
  }

  const footer = (
    <>
      <button type="button" className="btn" onClick={onClose} disabled={busy}>
        {t('cancel')}
      </button>
      <button type="submit" className="btn primary" disabled={busy}>
        {busy ? t('saving') : t('fbSend')}
      </button>
    </>
  )

  return (
    <Dialog title={t('fbH')} onClose={onClose} onSubmit={submit} footer={footer}>
      <div className="preview">
        {t('fbIntro', { v: APP_VERSION, r: t(profile.role) })}
        <div className="hint">{t('fbPrivacy')}</div>
      </div>

      <div className="field">
        <span className="lab">{t('fbQ1')}</span>
        <div className="seg seg-score">
          {SCORES.map((n) => (
            <label key={n}>
              <input
                type="radio"
                name="f-helpful"
                value={n}
                ref={n === 1 ? firstRef : undefined}
                checked={helpful === String(n)}
                onChange={(e) => {
                  setHelpful(e.target.value)
                  setErr('')
                }}
              />
              {n}
            </label>
          ))}
        </div>
        <p className="hint">
          {t('fbQ1Lo')} · {t('fbQ1Hi')}
        </p>
      </div>

      <div className="field">
        <label htmlFor="f-fb-issues">{t('fbQ2')}</label>
        <textarea
          id="f-fb-issues"
          rows={3}
          maxLength={FEEDBACK_ISSUES_MAX_LEN}
          placeholder={t('fbQ2Place')}
          value={issues}
          onChange={(e) => {
            setIssues(e.target.value)
            setErr('')
          }}
        />
      </div>

      {/* ถามเฉพาะ role ที่เกี่ยวข้อง — ทั้ง 2 ข้อเทียบกับ baseline ใน prd.md ข้อ 12 */}
      <div className="field">
        <label htmlFor="f-fb-count">{isOwner ? t('fbQ3') : t('fbQ4')}</label>
        <input
          id="f-fb-count"
          type="number"
          inputMode="numeric"
          step="1"
          min="0"
          value={count}
          onChange={(e) => {
            setCount(e.target.value)
            setErr('')
          }}
        />
        <p className="hint">{isOwner ? t('fbQ3Hint') : t('fbQ4Hint')}</p>
      </div>

      <p className="err" role="alert">
        {err}
      </p>
    </Dialog>
  )
}
