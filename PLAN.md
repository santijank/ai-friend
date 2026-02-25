# 📋 PLAN.md — แผนพัฒนา "ฟ้า AI Friend"

## แอป AI เพื่อนคู่ใจ — คุยเป็นธรรมชาติ เตือนกิจวัตร ดูแลทุกวัน

---

## 🎯 วิสัยทัศน์

สร้างแอป AI เพื่อนที่คนไทยเปิดใช้ทุกวัน เหมือนมีเพื่อนสนิทอยู่ในมือถือ
รู้จักเรา จำเรื่องที่เคยคุย ห่วงใยเรา เตือนกิจวัตร ให้กำลังใจ

**โมเดลธุรกิจ:** ฟรีสำหรับผู้ใช้ → หารายได้จากโฆษณา + Premium

---

## 📊 สถานะปัจจุบัน — สิ่งที่สร้างเสร็จแล้ว

### Backend (Python FastAPI) ✅
| ไฟล์ | สถานะ | หน้าที่ |
|------|--------|---------|
| `main.py` | ✅ เสร็จ | API endpoints: /register, /chat, /reminders, /auth/social |
| `ai_brain.py` | ✅ เสร็จ | System Prompt ภาษาไทย + Local Quick Reply + Claude Haiku |
| `database.py` | ✅ เสร็จ | SQLite: users, messages, reminders |
| `memory.py` | ✅ เสร็จ | จำข้อมูลผู้ใช้อัตโนมัติจากบทสนทนา |
| `Dockerfile` | ✅ เสร็จ | พร้อม deploy Railway |
| `railway.json` | ✅ เสร็จ | Config สำหรับ Railway |
| `requirements.txt` | ✅ เสร็จ | Dependencies |

### Flutter App ✅
| ไฟล์ | สถานะ | หน้าที่ |
|------|--------|---------|
| `main.dart` | ✅ เสร็จ | Entry point + init services |
| `config.dart` | ✅ เสร็จ | ตั้งค่า API URL |
| `models/message.dart` | ✅ เสร็จ | โมเดลข้อความ |
| `screens/onboarding_screen.dart` | ✅ เสร็จ | Onboarding แบบสนทนา |
| `screens/chat_screen.dart` | ✅ เสร็จ | หน้าแชทหลัก + Voice Input |
| `services/api_service.dart` | ✅ เสร็จ | เชื่อมต่อ Backend |
| `services/local_storage.dart` | ✅ เสร็จ | เก็บข้อมูลในเครื่อง (Hive) |
| `services/notification_service.dart` | ✅ เสร็จ | เตือนกิจวัตร Local Notification |
| `services/tts_service.dart` | ✅ เสร็จ | AI พูดตอบ (Text-to-Speech) |
| `services/stt_service.dart` | ✅ เสร็จ | พูดใส่แอป (Speech-to-Text) |
| `services/auth_service.dart` | ✅ เสร็จ | Device ID login + เตรียม Social Login |
| `widgets/chat_bubble.dart` | ✅ เสร็จ | กล่องข้อความ + ปุ่มฟังเสียง |
| `widgets/typing_indicator.dart` | ✅ เสร็จ | แสดงว่า AI กำลังพิมพ์ |
| `widgets/speak_button.dart` | ✅ เสร็จ | ปุ่มฟังเสียงข้อความ |
| `widgets/voice_button.dart` | ✅ เสร็จ | ปุ่มไมค์ + Listening Overlay |

### เอกสาร
| ไฟล์ | สถานะ | หน้าที่ |
|------|--------|---------|
| `README.md` | ✅ เสร็จ | วิธี setup + deploy ทั้งหมด |
| `VOICE_SETUP.md` | ✅ เสร็จ | ตั้งค่า permissions เสียง |
| `PLAN.md` | ✅ เสร็จ | แผนพัฒนาทั้งหมด (ไฟล์นี้) |

---

## 🏗️ สถาปัตยกรรมระบบ

```
┌──────────────────────────────────────────────────┐
│                   📱 Flutter App                  │
│                                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ Chat UI  │ │  Voice   │ │ Local Storage    │  │
│  │ + Bubble │ │ STT/TTS  │ │ Hive + SQLite    │  │
│  └────┬─────┘ └──────────┘ │ - chat history   │  │
│       │                     │ - user prefs     │  │
│       │  ┌──────────────┐  │ - offline cache  │  │
│       │  │ Notification │  └──────────────────┘  │
│       │  │ Local Push   │                         │
│       │  └──────────────┘                         │
└───────┼───────────────────────────────────────────┘
        │ HTTPS
        ▼
┌──────────────────────────────────────────────────┐
│              ☁️ Backend (FastAPI)                  │
│              Railway: $5/เดือน                     │
│                                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ 2-Layer  │ │ Memory   │ │ Reminder Engine  │  │
│  │ Router   │ │ Manager  │ │                  │  │
│  │ Local→   │ │ Auto     │ │ Parse from AI    │  │
│  │ Haiku    │ │ Extract  │ │ → Notify client  │  │
│  └──────────┘ └──────────┘ └──────────────────┘  │
│                                                    │
│  SQLite (users + messages + reminders)            │
└───────────────────┬──────────────────────────────┘
                    │
                    ▼
           Claude Haiku API
           ~$0.25/1M tokens
```

---

## 🚀 แผนพัฒนา 4 Phases

---

### Phase 1: MVP — เปิดใช้ได้ (สัปดาห์ที่ 1-4)

**เป้าหมาย:** แอปทำงานได้จริง ปล่อยให้คนใช้ได้

#### สัปดาห์ที่ 1: Setup + Backend
| งาน | รายละเอียด | สถานะ |
|------|-----------|--------|
| สมัคร Anthropic API | ได้ API key สำหรับ Claude Haiku | ⬜ ยังไม่ทำ |
| สมัคร Railway | สร้าง account + project | ⬜ ยังไม่ทำ |
| Deploy Backend | push code → Railway ให้ URL | ⬜ ยังไม่ทำ |
| ตั้ง Environment Variable | ANTHROPIC_API_KEY บน Railway | ⬜ ยังไม่ทำ |
| ทดสอบ API | ยิง curl ทดสอบ /register, /chat | ⬜ ยังไม่ทำ |

#### สัปดาห์ที่ 2: Flutter App
| งาน | รายละเอียด | สถานะ |
|------|-----------|--------|
| ติดตั้ง Flutter SDK | ตาม docs.flutter.dev | ⬜ ยังไม่ทำ |
| สร้างโปรเจกต์ Flutter | flutter create + คัดลอกโค้ด | ⬜ ยังไม่ทำ |
| ตั้งค่า config.dart | ใส่ URL จาก Railway | ⬜ ยังไม่ทำ |
| ตั้งค่า Android permissions | RECORD_AUDIO, INTERNET, NOTIFICATIONS | ⬜ ยังไม่ทำ |
| flutter pub get | ติดตั้ง packages | ⬜ ยังไม่ทำ |
| ทดสอบบน Emulator | รัน flutter run | ⬜ ยังไม่ทำ |

#### สัปดาห์ที่ 3: ทดสอบ + แก้บัค
| งาน | รายละเอียด | สถานะ |
|------|-----------|--------|
| ทดสอบ Onboarding | สมัคร → เลือกบุคลิก → ตั้งเวลา | ⬜ ยังไม่ทำ |
| ทดสอบแชท | คุยกับ AI ภาษาไทย 50+ ข้อความ | ⬜ ยังไม่ทำ |
| ทดสอบ Memory | AI จำชื่อ จำเรื่องที่เคยคุย | ⬜ ยังไม่ทำ |
| ทดสอบ Reminder | บอกนัด → AI ตั้ง notification | ⬜ ยังไม่ทำ |
| ทดสอบเสียง | STT พูดไทย → TTS AI พูดตอบ | ⬜ ยังไม่ทำ |
| ทดสอบบนเครื่องจริง | Android เครื่องจริง | ⬜ ยังไม่ทำ |
| แก้บัค | ปรับปรุงจากการทดสอบ | ⬜ ยังไม่ทำ |

#### สัปดาห์ที่ 4: ปล่อย Play Store
| งาน | รายละเอียด | สถานะ |
|------|-----------|--------|
| สมัคร Google Play Developer | จ่าย $25 ครั้งเดียว | ⬜ ยังไม่ทำ |
| สร้าง App Icon | ไอคอนแอป 512x512 | ⬜ ยังไม่ทำ |
| สร้าง Screenshots | จับภาพหน้าจอ 4-6 รูป | ⬜ ยังไม่ทำ |
| เขียนรายละเอียดแอป | ชื่อ คำอธิบาย หมวดหมู่ | ⬜ ยังไม่ทำ |
| สร้าง Privacy Policy | หน้าเว็บ privacy policy (ใช้ GitHub Pages ฟรี) | ⬜ ยังไม่ทำ |
| flutter build apk --release | Build APK | ⬜ ยังไม่ทำ |
| อัพโหลดขึ้น Play Store | Play Console → สร้าง release | ⬜ ยังไม่ทำ |
| รอ Google Review | ปกติ 1-7 วัน | ⬜ ยังไม่ทำ |

**💰 ค่าใช้จ่าย Phase 1:**
| รายการ | ราคา |
|--------|------|
| Railway Hobby | ₿175/เดือน |
| Claude Haiku API | ₿500-2,000/เดือน |
| Google Play Developer | ₿875 (ครั้งเดียว) |
| **รวม** | **~₿1,550-3,050 เดือนแรก** |
| **รวม** | **~₿675-2,175 เดือนถัดไป** |

---

### Phase 2: ปรับปรุง + หาผู้ใช้ (เดือนที่ 2-3)

**เป้าหมาย:** 1,000-5,000 ผู้ใช้

#### ฟีเจอร์ใหม่ที่ต้องสร้าง

| ฟีเจอร์ | ไฟล์ที่ต้องสร้าง/แก้ | สถานะ | สำคัญ |
|---------|---------------------|--------|-------|
| **Mood Tracker** | `widgets/mood_picker.dart`, แก้ `chat_screen.dart` | ✅ เสร็จ | ⭐⭐⭐⭐⭐ |
| **สรุปเช้า (Morning Brief)** | `services/morning_service.dart`, `backend/morning_brief.py` | ✅ เสร็จ | ⭐⭐⭐⭐⭐ |
| **สรุปก่อนนอน (Night Wrap)** | `services/night_service.dart`, `backend/morning_brief.py` | ✅ เสร็จ | ⭐⭐⭐⭐ |
| **หน้ากิจวัตร (Routine Page)** | `screens/routine_screen.dart`, `models/routine.dart` | ✅ เสร็จ | ⭐⭐⭐⭐ |
| **หน้าตั้งค่า** | `screens/settings_screen.dart` | ✅ เสร็จ | ⭐⭐⭐⭐ |
| **เปลี่ยนบุคลิก AI** | แก้ `settings_screen.dart`, `api_service.dart` | ✅ เสร็จ | ⭐⭐⭐ |
| **ธีมสี** | `services/theme_service.dart` | ✅ เสร็จ | ⭐⭐⭐ |
| **Bottom Navigation** | `screens/home_screen.dart`, แก้ `main.dart` | ✅ เสร็จ | ⭐⭐⭐⭐⭐ |
| **ประวัติอารมณ์ (กราฟ)** | `screens/mood_history_screen.dart` | ✅ เสร็จ | ⭐⭐⭐⭐ |
| **Google Sign-in** | แก้ `auth_service.dart`, เพิ่ม Firebase | ⬜ รอ Phase 3 | ⭐⭐⭐ |

#### Mood Tracker — รายละเอียด
```
ทุกวันตอนค่ำ AI ถาม:
🤖 "วันนี้รู้สึกยังไงบ้าง?"

ผู้ใช้เลือก:
😊 ดีมาก | 🙂 ดี | 😐 เฉย ๆ | 😔 ไม่ค่อยดี | 😢 แย่

→ เก็บเป็นข้อมูล → แสดงกราฟอารมณ์รายสัปดาห์
→ AI ใช้ข้อมูลนี้ปรับการตอบ

ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/widgets/mood_picker.dart        (UI เลือกอารมณ์)
- flutter_app/lib/screens/mood_history_screen.dart (กราฟอารมณ์)
- backend/main.py → เพิ่ม POST /mood, GET /mood/{user_id}
- backend/database.py → เพิ่มตาราง moods
```

#### สรุปเช้า (Morning Brief) — รายละเอียด
```
ทุกเช้าตามเวลาที่ตั้ง → Notification พร้อมข้อความ:

"☀️ อรุณสวัสดิ์มิน!
 วันนี้วันพุธ 26 ก.พ.
 - มีประชุม 10:00
 - นัดหมอ 14:00
 วันนี้จะเป็นวันที่ดีนะ!"

วิธีทำ (ประหยัด):
- ใช้ template + ดึง reminder ของวันนี้ → ไม่ต้องเรียก LLM
- สร้างข้อความบน server ส่งผ่าน Firebase Cloud Messaging

ไฟล์ที่ต้องสร้าง:
- backend/morning_brief.py       (สร้างข้อความสรุปเช้า)
- backend/scheduler.py           (APScheduler ส่งทุกเช้า)
- เพิ่ม Firebase Cloud Messaging (ส่ง push notification จาก server)
```

#### หน้ากิจวัตร (Routine Page) — รายละเอียด
```
┌──────────────────────────┐
│  📋 กิจวัตรวันนี้          │
│                            │
│  ✅ ตื่นนอน 7 โมง    +10⭐ │
│  ✅ กินข้าวเช้า        +5⭐ │
│  ☐  ออกกำลังกาย 30 นาที   │
│  ☐  อ่านหนังสือ            │
│  ☐  นอนก่อน 5 ทุ่ม        │
│                            │
│  🔥 Streak: 5 วันติด      │
│  ⭐ สะสม: 280              │
│                            │
│  [+ เพิ่มกิจวัตร]          │
└──────────────────────────┘

ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/screens/routine_screen.dart
- flutter_app/lib/models/routine.dart
- flutter_app/lib/widgets/routine_card.dart
- backend/main.py → เพิ่ม CRUD /routines
- backend/database.py → เพิ่มตาราง routines, routine_logs
```

#### หน้าตั้งค่า — รายละเอียด
```
┌──────────────────────────┐
│  ⚙️ ตั้งค่า                │
│                            │
│  👤 โปรไฟล์                │
│     ชื่อ: มิน              │
│     บุคลิก AI: เพื่อนสนิท  │
│                            │
│  ⏰ เวลา                   │
│     ตื่น: 07:00            │
│     นอน: 23:00             │
│                            │
│  🔔 การแจ้งเตือน           │
│     เตือนเช้า: เปิด        │
│     เตือนก่อนนอน: เปิด     │
│     AI ทักระหว่างวัน: เปิด  │
│                            │
│  🔊 เสียง                  │
│     AI พูดอัตโนมัติ: ปิด    │
│     ความเร็ว: ปานกลาง      │
│                            │
│  🎨 ธีม                    │
│     สีหลัก: ฟ้า            │
│     โหมดมืด: ปิด           │
│                            │
│  🔗 เชื่อมต่อบัญชี          │
│     Google: ยังไม่เชื่อมต่อ  │
│                            │
│  🗑️ ลบข้อมูลทั้งหมด        │
└──────────────────────────┘

ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/screens/settings_screen.dart
```

#### Bottom Navigation — รายละเอียด
```
ปัจจุบัน: มีแค่หน้าแชท
เพิ่ม: Bottom Navigation Bar 3 แท็บ

┌─── Bottom Navigation ────┐
│ 💬 แชท │ 📋 กิจวัตร │ ⚙️ ตั้งค่า │
└──────────────────────────┘

ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/screens/home_screen.dart  (shell + bottom nav)
- แก้ main.dart → ชี้ไปที่ home_screen แทน chat_screen
```

#### การตลาดเพื่อหาผู้ใช้
| ช่องทาง | วิธีการ | ค่าใช้จ่าย |
|---------|---------|-----------|
| TikTok | ทำคลิปสั้นโชว์ AI คุยไทย | ฟรี |
| Twitter/X | โพสต์ตัวอย่างบทสนทนา | ฟรี |
| กลุ่ม Facebook | แชร์ในกลุ่ม AI/เทคโนโลยี | ฟรี |
| Pantip | รีวิวแอป | ฟรี |
| บอกเพื่อน | Word of mouth | ฟรี |

**💰 ค่าใช้จ่าย Phase 2: ~₿2,000-5,000/เดือน**

---

### Phase 3: หารายได้ (เดือนที่ 4-6)

**เป้าหมาย:** 5,000-20,000 ผู้ใช้ + เริ่มมีรายได้

#### ระบบโฆษณา

| ประเภท | วิธีทำ | รายได้คาดการณ์ |
|--------|--------|---------------|
| **Google AdMob Banner** | Banner ด้านล่างหน้าแชท | ~₿30-80 / 1,000 views |
| **Rewarded Ads** | ดูโฆษณา → ปลดล็อกฟีเจอร์ | ~₿100-300 / 1,000 views |
| **Native Ads** | AI แนะนำสินค้า partner ในแชท | ติดต่อ partner เอง |

```
ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/services/ad_service.dart      (จัดการ AdMob)
- flutter_app/lib/widgets/ad_banner.dart         (แสดง banner)
- flutter_app/lib/widgets/rewarded_ad_button.dart (ปุ่มดูโฆษณา)
- pubspec.yaml → เพิ่ม google_mobile_ads

ตั้งค่า:
- สมัคร Google AdMob → ได้ App ID + Ad Unit ID
- ตั้งค่าใน AndroidManifest.xml และ Info.plist
```

#### ระบบ Premium (Freemium)

```
┌─────────────────────────────────────────┐
│  แผนการใช้งาน                            │
│                                           │
│  🆓 ฟรี                                  │
│  ├── 30 ข้อความ/วัน                      │
│  ├── มีโฆษณา                             │
│  ├── บุคลิก AI 2 แบบ                     │
│  └── ฟีเจอร์พื้นฐาน                      │
│                                           │
│  ⭐ Premium ₿59/เดือน                    │
│  ├── ไม่จำกัดข้อความ                      │
│  ├── ไม่มีโฆษณา                          │
│  ├── บุคลิก AI 4 แบบ + สร้างเอง          │
│  ├── Voice chat ไม่จำกัด                  │
│  └── สรุปสัปดาห์/เดือน                    │
│                                           │
│  💎 Premium+ ₿149/เดือน                  │
│  ├── ทุกอย่างใน Premium                   │
│  ├── ใช้โมเดล AI ตัวแรง (Sonnet)          │
│  ├── AI วิเคราะห์ mood trends             │
│  ├── ส่งรูปถามได้                         │
│  └── Priority support                    │
└─────────────────────────────────────────┘

ไฟล์ที่ต้องสร้าง:
- flutter_app/lib/services/subscription_service.dart
- flutter_app/lib/screens/premium_screen.dart
- backend/main.py → เพิ่ม middleware เช็ค subscription
- ตั้งค่า Google Play Billing / Apple In-App Purchase
```

#### ระบบจำกัดข้อความ (Rate Limiting)
```
ไฟล์ที่ต้องแก้:
- backend/main.py → เพิ่มเช็คจำนวนข้อความต่อวัน
- backend/database.py → เพิ่มนับข้อความรายวัน
- flutter_app/lib/screens/chat_screen.dart → แสดงจำนวนที่เหลือ
```

**💰 รายได้คาดการณ์ Phase 3:**
| ผู้ใช้ | รายได้ AdMob | รายได้ Premium | รวม |
|--------|-------------|---------------|-----|
| 5,000 | ~₿5,000-15,000 | ~₿3,000-5,000 | ~₿8,000-20,000 |
| 10,000 | ~₿10,000-30,000 | ~₿8,000-15,000 | ~₿18,000-45,000 |
| 20,000 | ~₿20,000-60,000 | ~₿15,000-30,000 | ~₿35,000-90,000 |

**💰 ค่าใช้จ่าย Phase 3: ~₿5,000-15,000/เดือน**
**📈 จุดคุ้มทุน: ~8,000-15,000 active users**

---

### Phase 4: Scale + ฟีเจอร์ขั้นสูง (เดือนที่ 7-12)

**เป้าหมาย:** 50,000+ ผู้ใช้ + กำไร

#### ฟีเจอร์ขั้นสูง

| ฟีเจอร์ | รายละเอียด | ไฟล์ที่ต้องสร้าง |
|---------|-----------|-----------------|
| **AI Vision (ส่งรูปถาม)** | ถ่ายรูปอาหาร → AI บอกแคลอรี่ | `services/image_service.dart`, แก้ `chat_screen.dart` |
| **Voice Chat Mode** | คุยด้วยเสียงแบบ real-time | `screens/voice_chat_screen.dart` |
| **AI Proactive** | AI ทักมาเองระหว่างวัน | `backend/proactive.py`, Firebase Cloud Messaging |
| **Group AI** | เพิ่มเพื่อน ใช้ AI ร่วมกัน | `backend/groups.py`, `screens/group_screen.dart` |
| **Mini Games** | เกมเล็ก ๆ เล่นกับ AI | `screens/game_screen.dart` |
| **Mood Analytics** | กราฟ + insight จาก AI | `screens/analytics_screen.dart` |
| **Widget หน้าจอ** | Widget แสดงกิจวัตรบน home screen | Android/iOS widget config |
| **Apple Watch / Wear OS** | เตือนกิจวัตรบนนาฬิกา | companion app |

#### ปรับปรุง Infrastructure
```
เมื่อมีผู้ใช้ 50,000+ ต้อง:

1. ย้ายจาก SQLite → PostgreSQL
   - ไฟล์แก้: backend/database.py
   - ใช้ Supabase หรือ Railway PostgreSQL

2. เพิ่ม Redis สำหรับ caching
   - cache คำตอบ AI ที่ซ้ำกัน
   - cache user session

3. ย้ายไป Container ที่ใหญ่ขึ้น
   - Railway Pro หรือ DigitalOcean

4. เพิ่ม Vector DB สำหรับ memory ที่ดีขึ้น
   - ChromaDB หรือ pgvector
   - ดึง memory ที่เกี่ยวข้องได้แม่นยำขึ้น

5. เพิ่ม CDN + Load Balancer
   - ถ้าขยายไป multi-region
```

**💰 ค่าใช้จ่าย Phase 4: ~₿15,000-50,000/เดือน**
**📈 รายได้เป้าหมาย: ~₿100,000-300,000/เดือน**

---

## 📂 โครงสร้างไฟล์เป้าหมาย (ทุก Phase รวม)

```
ai-friend-project/
│
├── 📄 README.md                          ✅ เสร็จ
├── 📄 PLAN.md                            ✅ เสร็จ
│
├── backend/
│   ├── 📄 main.py                        ✅ เสร็จ
│   ├── 📄 ai_brain.py                    ✅ เสร็จ
│   ├── 📄 database.py                    ✅ เสร็จ
│   ├── 📄 memory.py                      ✅ เสร็จ
│   ├── 📄 morning_brief.py              ✅ เสร็จ
│   ├── 📄 scheduler.py                  ⬜ Phase 3 (APScheduler)
│   ├── 📄 proactive.py                  ⬜ Phase 4
│   ├── 📄 Dockerfile                     ✅ เสร็จ
│   ├── 📄 railway.json                   ✅ เสร็จ
│   └── 📄 requirements.txt              ✅ เสร็จ
│
└── flutter_app/
    ├── 📄 pubspec.yaml                   ✅ เสร็จ
    ├── 📄 VOICE_SETUP.md                 ✅ เสร็จ
    │
    └── lib/
        ├── 📄 main.dart                  ✅ เสร็จ
        ├── 📄 config.dart                ✅ เสร็จ
        │
        ├── models/
        │   ├── 📄 message.dart           ✅ เสร็จ
        │   └── 📄 routine.dart           ✅ เสร็จ
        │
        ├── screens/
        │   ├── 📄 onboarding_screen.dart ✅ เสร็จ
        │   ├── 📄 chat_screen.dart       ✅ เสร็จ
        │   ├── 📄 home_screen.dart       ✅ เสร็จ (bottom nav)
        │   ├── 📄 routine_screen.dart    ✅ เสร็จ
        │   ├── 📄 settings_screen.dart   ✅ เสร็จ
        │   ├── 📄 mood_history_screen.dart ✅ เสร็จ
        │   ├── 📄 premium_screen.dart    ⬜ Phase 3
        │   ├── 📄 voice_chat_screen.dart ⬜ Phase 4
        │   ├── 📄 analytics_screen.dart  ⬜ Phase 4
        │   └── 📄 game_screen.dart       ⬜ Phase 4
        │
        ├── services/
        │   ├── 📄 api_service.dart       ✅ เสร็จ
        │   ├── 📄 local_storage.dart     ✅ เสร็จ
        │   ├── 📄 notification_service.dart ✅ เสร็จ
        │   ├── 📄 tts_service.dart       ✅ เสร็จ
        │   ├── 📄 stt_service.dart       ✅ เสร็จ
        │   ├── 📄 auth_service.dart      ✅ เสร็จ
        │   ├── 📄 morning_service.dart   ✅ เสร็จ
        │   ├── 📄 night_service.dart     ✅ เสร็จ
        │   ├── 📄 theme_service.dart     ✅ เสร็จ
        │   ├── 📄 ad_service.dart        ⬜ Phase 3
        │   ├── 📄 subscription_service.dart ⬜ Phase 3
        │   └── 📄 image_service.dart     ⬜ Phase 4
        │
        └── widgets/
            ├── 📄 chat_bubble.dart       ✅ เสร็จ
            ├── 📄 typing_indicator.dart  ✅ เสร็จ
            ├── 📄 speak_button.dart      ✅ เสร็จ
            ├── 📄 voice_button.dart      ✅ เสร็จ
            ├── 📄 mood_picker.dart       ✅ เสร็จ
            ├── 📄 routine_card.dart      ✅ เสร็จ
            ├── 📄 ad_banner.dart         ⬜ Phase 3
            └── 📄 rewarded_ad_button.dart ⬜ Phase 3
```

---

## 💰 สรุปค่าใช้จ่าย vs รายได้

```
                   ค่าใช้จ่าย        รายได้         กำไร/ขาดทุน
                   ──────────       ──────────     ──────────
Phase 1 (MVP)      ₿2,000/เดือน    ₿0             -₿2,000
Phase 2 (5K users) ₿5,000/เดือน    ₿0             -₿5,000
Phase 3 (10K)      ₿10,000/เดือน   ₿20,000-45,000 +₿10,000-35,000 ✅
Phase 4 (50K)      ₿30,000/เดือน   ₿100,000-300,000 +₿70,000-270,000 ✅

เงินลงทุนรวมก่อนคุ้มทุน: ~₿30,000-50,000 (3-5 เดือน)
```

---

## 🎯 KPIs ที่ต้องติดตาม

| ตัวชี้วัด | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|-----------|---------|---------|---------|---------|
| ผู้ใช้ทั้งหมด | 100 | 5,000 | 20,000 | 50,000+ |
| Active users/วัน | 30 | 1,500 | 6,000 | 20,000 |
| ข้อความ/คน/วัน | 20 | 25 | 30 | 30 |
| Retention วัน 7 | 30% | 40% | 50% | 55% |
| Retention วัน 30 | 10% | 20% | 30% | 35% |
| ค่า API/คน/วัน | ₿2 | ₿1.5 | ₿1 | ₿0.8 |
| รายได้/คน/เดือน | - | - | ₿3-5 | ₿5-8 |

---

## ⚡ Quick Start — เริ่มทำวันนี้

```bash
# 1. สมัคร Anthropic API Key
#    → https://console.anthropic.com

# 2. สมัคร Railway
#    → https://railway.app

# 3. Deploy Backend
cd backend
# push ขึ้น GitHub → เชื่อม Railway → ตั้ง ANTHROPIC_API_KEY

# 4. ติดตั้ง Flutter
#    → https://docs.flutter.dev/get-started/install

# 5. สร้างแอป
cd flutter_app
flutter create ai_friend --org com.yourname
# คัดลอกไฟล์จาก lib/ ไปใส่

# 6. ตั้งค่า
# แก้ lib/config.dart → ใส่ URL จาก Railway
# แก้ android/app/src/main/AndroidManifest.xml → เพิ่ม permissions

# 7. รัน
flutter pub get
flutter run

# 8. ปล่อย Play Store
flutter build apk --release
# อัพโหลดผ่าน play.google.com/console
```

---

*อัพเดทล่าสุด: กุมภาพันธ์ 2026*
*สร้างโดย: AI Friend Development Team*
