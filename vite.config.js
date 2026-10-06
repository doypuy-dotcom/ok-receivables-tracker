import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    // PWA (M6) — ดู docs/architecture.md ข้อ 8
    VitePWA({
      // 'prompt' = มีเวอร์ชันใหม่แล้วถามผู้ใช้ก่อน ไม่รีโหลดเองกลางคัน (ผู้ใช้อาจกำลังกรอกฟอร์มอยู่)
      registerType: 'prompt',
      injectRegister: null, // ลงทะเบียน service worker เองใน src/components/UpdatePrompt.jsx
      manifest: {
        id: '/',
        name: 'ระบบติดตามยอดค้างชำระ — OK',
        short_name: 'OK ยอดค้าง',
        description: 'ยอดค้างชำระของแต่ละบริษัท แยกตามเดือนที่ครบกำหนด',
        lang: 'th',
        dir: 'ltr',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: '#f2f5f4', // --bg
        theme_color: '#1c5da3', // --primary จาก docs/ui-reference.html
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          {
            src: '/icons/icon-512-maskable.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // cache เฉพาะไฟล์ของแอป (app shell) ที่ build ออกมา
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest}'],
        // เปิด URL ตรง เช่น /r/<id> ตอนไม่มีเน็ต → ได้ index.html จาก cache แล้ว react-router จัดการต่อ
        navigateFallback: '/index.html',
        // **ห้าม cache คำขอไป Supabase ทุกชนิด** (ข้อมูล, auth, realtime) และฟอนต์จาก Google
        // ไม่มี runtimeCaching = service worker ไม่แตะคำขอข้ามโดเมนเลย ทุกคำขอวิ่งออกเน็ตจริงเสมอ
        // ถ้าไม่มีสัญญาณ คำขอจะล้มเหลวแล้วแอปขึ้นข้อความ "ออฟไลน์" แทนตัวเลขเก่า
        runtimeCaching: [],
        cleanupOutdatedCaches: true,
        // service worker ใหม่รอจนผู้ใช้กดอัปเดต (หรือปิดแอปทุกหน้าต่างแล้วเปิดใหม่)
        skipWaiting: false,
        clientsClaim: false,
      },
    }),
  ],
})
