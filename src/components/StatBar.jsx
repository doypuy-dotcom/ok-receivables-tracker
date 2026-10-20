// แถบสัดส่วนของหน้าสถิติ (V2 ข้อ 3) — ทำด้วย CSS ล้วน ไม่ติดตั้งไลบรารีกราฟ
// ใช้โครงเดียวกับแถบในการ์ด (.bar / .bar-top / .track / .fill) จึงได้สีและความสูงชุดเดียวกัน
//
// **pct เป็นข้อความ % ที่ database คำนวณมาแล้ว** (เช่น "68.40") เอาไปต่อเป็น width: 68.40%
// ตรง ๆ แอปไม่ได้หาร ไม่ได้เทียบ ไม่ได้ปัดเศษอะไรเลย (AGENTS.md)
// แถบเป็นภาพประกอบของตัวเลขที่พิมพ์อยู่ข้าง ๆ จึง aria-hidden ไม่ต้องให้โปรแกรมอ่านจอซ้ำ
export default function StatBar({ label, value, pct, tone = '', sub }) {
  return (
    <div className="bar">
      <div className="bar-top">
        <span>{label}</span>
        <span className="pct num">{value}</span>
      </div>
      <div className="track" aria-hidden="true">
        <div className={'fill ' + tone} style={{ width: `${pct ?? 0}%` }} />
      </div>
      {sub ? <div className="sub num">{sub}</div> : null}
    </div>
  )
}
