// ส่วน "หมายเหตุ" ในหน้ารายละเอียดการ์ด (V1 รอบ ข — prd.md ข้อ 5 รายการที่ 11, schema.md 3.6)
// ทุกรายการ: ใครเขียน + เมื่อไหร่ + ข้อความ · ใหม่ → เก่า (เหมือนประวัติการแก้ไข)
// ฝ่ายขายเขียนได้ เจ้าของอ่านอย่างเดียว — ไม่มีปุ่มแก้/ลบให้ใคร เพราะตารางเป็นแบบต่อท้ายอย่างเดียว
// (เขียนผิด → เขียนรายการใหม่ ทั้ง 2 รายการยังอยู่ จึงเป็นประวัติในตัว)
import { useState } from 'react'
import { insertNote, NOTE_MAX_LEN } from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { fmtStamp } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

export default function NotesPanel({ receivableId, notes, userNames, canWrite, onSaved }) {
  const { t, lang } = useLang()
  const [body, setBody] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    if (busy) return
    // trim ก่อนส่งให้ตรงกับ constraint receivable_notes_body_trimmed
    const clean = body.trim()
    if (!clean) {
      setErr(t('eNoteEmpty'))
      return
    }
    if (clean.length > NOTE_MAX_LEN) {
      setErr(t('eNoteLong', { n: NOTE_MAX_LEN }))
      return
    }
    setBusy(true)
    const { error } = await insertNote(receivableId, clean)
    setBusy(false)
    if (error) {
      setErr(t(saveErrorKey(error)))
      return
    }
    setBody('')
    setErr('')
    onSaved(t('noteSaved'))
  }

  return (
    <>
      <h2>{t('notesH')}</h2>
      {notes.length === 0 ? (
        <div className="empty">{t('noNotes')}</div>
      ) : (
        <ul className="notes">
          {notes.map((n) => (
            <li key={n.id}>
              <div className="note-head">
                <b>{userNames[n.created_by] ?? t('unknownUser')}</b>
                <span className="num">{fmtStamp(lang, n.created_at)}</span>
              </div>
              <p className="note-body">{n.body}</p>
            </li>
          ))}
        </ul>
      )}

      {/* เจ้าของอ่านอย่างเดียว (prd ข้อ 9) จึงไม่เห็นช่องเขียนเลย — สิทธิ์จริงบังคับด้วย RLS */}
      {canWrite && (
        <form className="note-form" onSubmit={submit}>
          <div className="field">
            <label htmlFor="f-note">{t('noteNew')}</label>
            <textarea
              id="f-note"
              rows={3}
              maxLength={NOTE_MAX_LEN}
              placeholder={t('notePlace')}
              value={body}
              onChange={(e) => {
                setBody(e.target.value)
                setErr('')
              }}
            />
            <p className="hint">
              {t('noteRule')} · <span className="num">{t('noteLeft', { n: NOTE_MAX_LEN - body.length })}</span>
            </p>
          </div>
          <p className="panel-actions">
            <button type="submit" className="btn primary" disabled={busy}>
              {busy ? t('saving') : t('noteAdd')}
            </button>
          </p>
          <p className="err" role="alert">
            {err}
          </p>
        </form>
      )}
    </>
  )
}
