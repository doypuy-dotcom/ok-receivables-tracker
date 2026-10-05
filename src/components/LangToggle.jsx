import { useLang } from '../lib/i18n.js'

export default function LangToggle() {
  const { lang, setLang } = useLang()
  return (
    <div className="lang" role="group" aria-label="Language">
      <button type="button" aria-pressed={lang === 'en'} onClick={() => setLang('en')}>
        ENG
      </button>
      <button type="button" aria-pressed={lang === 'th'} onClick={() => setLang('th')}>
        ไทย
      </button>
    </div>
  )
}
