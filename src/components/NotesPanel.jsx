// ส่วน "หมายเหตุ" ในหน้ารายละเอียดการ์ด (V1 รอบ ข — prd.md ข้อ 5 รายการที่ 11, schema.md 3.6)
// ทุกรายการ: ใครเขียน + ป้ายว่าเป็นเจ้าของหรือฝ่ายขาย + เมื่อไหร่ + ข้อความ · ใหม่ → เก่า
// **V2 ข้อ 2: เจ้าของเขียนได้ด้วย** (migration 007 — feedback อาจารย์ 20 ต.ค. 2569:
// เจ้าของต้องติดต่อฝ่ายขายได้ ไม่ใช่ดูอย่างเดียว) จึงเป็นช่องคุยกันบนการ์ดใบนั้น
// ไม่มีปุ่มแก้/ลบให้ใคร เพราะตารางเป็นแบบต่อท้ายอย่างเดียว
// (เขียนผิด → เขียนรายการใหม่ ทั้ง 2 รายการยังอยู่ จึงเป็นประวัติในตัว)
// หมายเหตุของเจ้าของทำสีให้เด่น เพื่อให้ฝ่ายขายเห็นว่ามีเรื่องฝากไว้
import { useState } from 'react'
import { insertNote, NOTE_MAX_LEN } from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { fmtStamp } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

export default function NotesPanel({ receivableId, notes, userNames, userRoles, myRole, canWrite, onSaved }) {
  const { t, lang } = useLang()
  const [body, setBody] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const iAmOwner = myRole === 'owner'

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
          {notes.map((n) => {
            // role ของคนเขียนมาจาก profiles ที่หน้านี้โหลดไว้แล้ว (ไม่รู้ = ไม่ติดป้าย)
            const role = userRoles?.[n.created_by]
            return (
              <li key={n.id} className={role === 'owner' ? 'from-owner' : undefined}>
                <div className="note-head">
                  <b>{userNames[n.created_by] ?? t('unknownUser')}</b>
                  {role && <b className={'note-who ' + role}>{t(role === 'owner' ? 'byOwner' : 'bySales')}</b>}
                  <span className="num">{fmtStamp(lang, n.created_at)}</span>
                </div>
                <p className="note-body">{n.body}</p>
              </li>
            )
          })}
        </ul>
      )}

      {/* เจ้าของและฝ่ายขายเขียนได้ทั้งคู่ (prd ข้อ 9) — สิทธิ์จริงบังคับด้วย RLS */}
      {canWrite && (
        <form className="note-form" onSubmit={submit}>
          <div className="field">
            <label htmlFor="f-note">{t('noteNew')}</label>
            <textarea
              id="f-note"
              rows={3}
              maxLength={NOTE_MAX_LEN}
              placeholder={t(iAmOwner ? 'notePlaceOwner' : 'notePlace')}
              value={body}
              onChange={(e) => {
                setBody(e.target.value)
                setErr('')
              }}
            />
            <p className="hint">
              {iAmOwner ? t('noteOwnerHint') + ' · ' : ''}
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
