// Realtime — รู้ว่า "มีของใหม่" แล้วโหลดข้อมูลใหม่ทั้งก้อน (architecture.md ข้อ 7)
// ไม่คำนวณอะไรจากตัว event เลย: event เป็นแค่สัญญาณ ค่าทุกตัวยังมาจาก receivable_summary / ตาราง
// ตารางที่เปิด Realtime อยู่ใน supabase/migrations/004_realtime.sql และ Realtime กรองตาม RLS ให้แล้ว
//
// รวบ event ที่มาติดกันเป็นการโหลดครั้งเดียว: การบันทึก 1 ครั้งทำให้เกิดหลาย event เสมอ
// (แถวในตารางหลัก + แถวใน audit_logs ที่ trigger เขียน และบางงานแตะหลายตาราง เช่น
// สร้างบริษัทใหม่พร้อมการ์ด) ถ้าโหลดทุก event หน้าจอจะยิงคำขอซ้ำ ๆ โดยไม่ได้อะไรเพิ่ม
//
// โหลดใหม่เสมอเมื่อกลับมาที่แท็บ / แอป (visibilitychange, focus, pageshow) หรือเน็ตกลับมา (online)
// เพราะมือถือมักตัด websocket ตอนพักแอป แล้ว event ช่วงนั้นหายไปเงียบ ๆ — เชื่อ Realtime อย่างเดียวไม่ได้
import { useEffect, useRef } from 'react'
import { supabase } from './supabase.js'

// ตารางที่เปิด Realtime ใน 004_realtime.sql และ 005_notes_and_feedback.sql (receivable_notes)
// app_feedback ไม่อยู่ในนี้: ไม่มีหน้าจอไหนต้องอัปเดตตาม และอ่านได้แค่แถวของตัวเอง
const TABLES = ['companies', 'receivables', 'payments', 'audit_logs', 'receivable_notes']

// หน่วงก่อนโหลด: รวบ event ที่มาติดกันจากการบันทึกครั้งเดียวให้เป็นการโหลดครั้งเดียว
const BURST_MS = 400

// ชื่อ channel ไม่ซ้ำกัน: ตอนเปลี่ยนหน้า หน้าใหม่ subscribe ก่อนที่หน้าเก่าจะ unsubscribe เสร็จ
let channelSeq = 0

/**
 * subscribe การเปลี่ยนแปลงของตารางหลัก แล้วเรียก `reload` (โหลดข้อมูลของหน้านั้นใหม่)
 * เรียกได้หน้าเดียวต่อ 1 component — `reload` เปลี่ยนได้ทุก render โดยไม่ต่อ channel ใหม่
 */
export function useLiveReload(reload) {
  const reloadRef = useRef(reload)

  useEffect(() => {
    reloadRef.current = reload
  }, [reload])

  useEffect(() => {
    if (!supabase) return

    let timer = null
    let stopped = false

    const schedule = () => {
      if (stopped || timer !== null) return
      timer = setTimeout(() => {
        timer = null
        if (!stopped) reloadRef.current()
      }, BURST_MS)
    }

    const channel = supabase.channel(`ok-live-${++channelSeq}`)
    for (const table of TABLES) {
      channel.on('postgres_changes', { event: '*', schema: 'public', table }, schedule)
    }

    let subscribedBefore = false
    channel.subscribe((status) => {
      if (status !== 'SUBSCRIBED') return
      // ต่อใหม่หลังหลุด (พักแอป / เน็ตหลุด): ช่วงที่หลุดอาจมี event ที่ไม่ได้รับ → โหลดใหม่
      if (subscribedBefore) schedule()
      subscribedBefore = true
    })

    const wake = () => {
      if (document.visibilityState === 'hidden') return
      // websocket มักตายตอนมือถือพักแอป — สั่งต่อใหม่ (ไม่ทำอะไรถ้ายังต่ออยู่หรือกำลังต่อ)
      // ต่อไม่ได้ก็ไม่เป็นไร: การโหลดข้อมูลใหม่ด้านล่างสำคัญกว่าและทำงานแยกกัน
      try {
        supabase.realtime.connect()
      } catch {
        // ไม่มี websocket ในสภาพแวดล้อมนี้ → ใช้การโหลดใหม่ตอนกลับมาที่แอปอย่างเดียว
      }
      schedule()
    }

    // persisted = true เท่านั้น: กลับมาจาก back/forward cache (iOS Safari กดย้อนกลับ)
    // ถ้าไม่เช็ค pageshow ของการเปิดหน้าครั้งแรกจะทำให้โหลดซ้ำทันทีหลังโหลดเสร็จ
    const onPageShow = (e) => {
      if (e.persisted) wake()
    }

    document.addEventListener('visibilitychange', wake)
    window.addEventListener('focus', wake)
    window.addEventListener('online', wake)
    window.addEventListener('pageshow', onPageShow)

    return () => {
      stopped = true
      if (timer !== null) clearTimeout(timer)
      document.removeEventListener('visibilitychange', wake)
      window.removeEventListener('focus', wake)
      window.removeEventListener('online', wake)
      window.removeEventListener('pageshow', onPageShow)
      supabase.removeChannel(channel)
    }
  }, [])
}
