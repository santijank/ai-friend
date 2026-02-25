# 🤖 ฟ้า AI Friend — AI เพื่อนคู่ใจ

แอปมือถือ AI เพื่อนที่คุยเป็นธรรมชาติ จำเรื่องที่เคยคุย และเตือนกิจวัตรประจำวัน

## 📁 โครงสร้างโปรเจกต์

```
ai-friend-project/
├── backend/                    # FastAPI Backend
│   ├── main.py                 # API endpoints (3 ตัว)
│   ├── ai_brain.py             # System Prompt + Claude Haiku
│   ├── memory.py               # จัดการ memory อัตโนมัติ
│   ├── database.py             # SQLite database
│   ├── requirements.txt
│   ├── Dockerfile
│   └── railway.json
│
└── flutter_app/                # Flutter Mobile App
    ├── lib/
    │   ├── main.dart           # Entry point
    │   ├── config.dart         # ตั้งค่า API URL
    │   ├── models/
    │   │   └── message.dart
    │   ├── screens/
    │   │   ├── onboarding_screen.dart  # ลงทะเบียนแบบสนทนา
    │   │   └── chat_screen.dart        # หน้าแชทหลัก
    │   ├── services/
    │   │   ├── api_service.dart        # เชื่อมต่อ Backend
    │   │   ├── local_storage.dart      # เก็บข้อมูลในเครื่อง (Hive)
    │   │   └── notification_service.dart # เตือนกิจวัตร
    │   └── widgets/
    │       ├── chat_bubble.dart        # กล่องข้อความ
    │       └── typing_indicator.dart   # แสดงว่า AI กำลังพิมพ์
    └── pubspec.yaml
```

---

## 🚀 วิธี Setup

### ขั้นตอนที่ 1: Backend

#### 1.1 รันบนเครื่อง (ทดสอบ)

```bash
cd backend

# สร้าง virtual environment
python -m venv venv
source venv/bin/activate        # Mac/Linux
# venv\Scripts\activate         # Windows

# ติดตั้ง dependencies
pip install -r requirements.txt

# ตั้งค่า API Key
export ANTHROPIC_API_KEY="sk-ant-xxxxx"    # Mac/Linux
# set ANTHROPIC_API_KEY=sk-ant-xxxxx       # Windows

# รัน server
uvicorn main:app --reload --port 8000
```

เปิด http://localhost:8000/docs จะเห็น API docs

#### 1.2 Deploy ขึ้น Railway

1. สมัครที่ [railway.app](https://railway.app)
2. สร้าง Project ใหม่ → **Deploy from GitHub repo**
3. เลือก folder `backend/`
4. ตั้ง Environment Variable:
   - `ANTHROPIC_API_KEY` = API key จาก console.anthropic.com
5. Railway จะให้ URL เช่น `https://xxx.up.railway.app`

---

### ขั้นตอนที่ 2: Flutter App

#### 2.1 ติดตั้ง Flutter

```bash
# ถ้ายังไม่มี Flutter
# ดูที่ https://docs.flutter.dev/get-started/install
```

#### 2.2 ตั้งค่า API URL

แก้ไฟล์ `flutter_app/lib/config.dart`:

```dart
// เปลี่ยนเป็น URL จาก Railway
static const String apiBaseUrl = 'https://your-app.up.railway.app';

// หรือตอนทดสอบ ใช้:
// Android Emulator: 'http://10.0.2.2:8000'
// iOS Simulator:    'http://localhost:8000'
// เครื่องจริง:       'http://192.168.x.x:8000' (IP ของ PC)
```

#### 2.3 รัน App

```bash
cd flutter_app

# ติดตั้ง packages
flutter pub get

# รันบน emulator/เครื่องจริง
flutter run
```

#### 2.4 Build APK (Android)

```bash
flutter build apk --release
# ได้ไฟล์ที่ build/app/outputs/flutter-apk/app-release.apk
```

#### 2.5 Build สำหรับ iOS

```bash
flutter build ios --release
# ต้องเปิดใน Xcode เพื่อ archive และ upload
```

---

## 🔑 สมัคร Anthropic API Key

1. ไปที่ https://console.anthropic.com
2. สร้าง Account
3. ไปที่ Settings → API Keys → Create Key
4. เก็บ key ไว้ใช้ตั้งค่า Backend

---

## 💰 ค่าใช้จ่ายโดยประมาณ

| รายการ | ราคา |
|--------|------|
| Railway Hobby Plan | $5/เดือน (~₿175) |
| Claude Haiku API (1,000 users) | ~$15-50/เดือน (~₿500-1,750) |
| Google Play Developer | $25 ครั้งเดียว (~₿875) |
| Apple Developer (ถ้าจะลง iOS) | $99/ปี (~₿3,300) |

**รวม MVP: ~₿675 - ₿2,000/เดือน**

---

## 📱 ฟีเจอร์ที่มี

- ✅ แชทกับ AI เป็นภาษาไทยเป็นธรรมชาติ
- ✅ AI จำชื่อ ข้อมูลส่วนตัว เรื่องที่เคยคุย
- ✅ ตั้งเตือนกิจวัตรอัตโนมัติ (บอก AI → ตั้ง notification)
- ✅ เลือกบุคลิก AI ได้ 4 แบบ
- ✅ ข้อความทักทายตอนเช้าทุกวัน
- ✅ Onboarding แบบสนทนา (ไม่ใช่ฟอร์ม)
- ✅ เก็บ chat history ในเครื่อง (เปิดแอปเห็นแชทเก่า)
- ✅ ตอบทักทายง่าย ๆ ได้ทันทีไม่ต้องเรียก API (ประหยัด)

---

## 🗺️ Roadmap ฟีเจอร์ถัดไป

- [ ] Mood tracker (บันทึกอารมณ์ประจำวัน)
- [ ] สรุปเช้า/ก่อนนอน
- [ ] Gamification (ดาว, streak)
- [ ] ธีม/สี ให้เลือก
- [ ] Voice chat
- [ ] โฆษณา AdMob
- [ ] Premium tier

---

## 🧪 ทดสอบ API ด้วย curl

```bash
# สมัคร
curl -X POST http://localhost:8000/register \
  -H "Content-Type: application/json" \
  -d '{"name": "มิน", "personality": "friendly"}'

# แชท (ใส่ user_id ที่ได้จากการสมัคร)
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"user_id": "abc12345", "message": "วันนี้เหนื่อยมากเลย"}'

# ดู reminders
curl http://localhost:8000/reminders/abc12345

# ดู memory
curl http://localhost:8000/memory/abc12345
```
