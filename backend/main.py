"""
main.py — AI Friend Backend
API endpoints ทั้งหมดสำหรับแอป ฟ้า AI Friend
"""

import io
import json
import re
import uuid
from datetime import datetime, date, timedelta
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import edge_tts

import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler

import database as db
from ai_brain import try_local_reply, call_haiku, parse_reminder_text
from memory import process_memory_update, get_memory_summary
from morning_brief import generate_morning_brief, generate_night_wrap
from news_fetcher import run_alert_fetch_job

logging.basicConfig(level=logging.INFO)


# ==================== App Setup ====================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """เริ่มต้น: สร้างตาราง DB + เริ่ม Alert Scheduler"""
    db.init_db()
    print("[OK] Database initialized")

    # เริ่ม APScheduler — ดึงข่าว/แผ่นดินไหวทุก 7 นาที
    scheduler = AsyncIOScheduler(timezone="Asia/Bangkok")
    scheduler.add_job(
        run_alert_fetch_job,
        trigger="interval",
        minutes=7,
        id="alert_fetch",
        name="Fetch earthquake and news alerts",
        replace_existing=True,
        max_instances=1,
        misfire_grace_time=60,
    )
    scheduler.start()
    print("[OK] Alert scheduler started (every 7 minutes)")

    # ดึงข้อมูลทันทีตอน start
    try:
        await run_alert_fetch_job()
        print("[OK] Initial alert fetch completed")
    except Exception as e:
        print(f"[WARN] Initial alert fetch failed: {e}")

    yield

    scheduler.shutdown(wait=False)
    print("[BYE] Scheduler stopped. Server shutting down")


app = FastAPI(title="AI Friend API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==================== Request/Response Models ====================

class RegisterRequest(BaseModel):
    name: str
    personality: str = "friendly"  # friendly, caring, cheerful, professional
    wake_time: str = "07:00"
    sleep_time: str = "23:00"


class RegisterResponse(BaseModel):
    user_id: str
    name: str
    personality: str
    message: str


class ChatRequest(BaseModel):
    user_id: str
    message: str


class ChatResponse(BaseModel):
    reply: str
    has_reminder: bool = False
    reminder_message: str | None = None
    reminder_time: str | None = None


class AlertItem(BaseModel):
    id: int
    alert_type: str
    severity: str
    title: str
    description: str
    source: str
    magnitude: float
    location: str
    url: str
    fetched_at: str


class ReminderItem(BaseModel):
    id: int
    message: str
    remind_at: str
    done: bool


class MoodRequest(BaseModel):
    user_id: str
    score: int  # 1-5 (1=แย่มาก, 5=ดีมาก)
    note: str = ""


class RoutineRequest(BaseModel):
    user_id: str
    title: str
    time: str = ""
    points: int = 5


class SettingsRequest(BaseModel):
    user_id: str
    personality: str | None = None
    wake_time: str | None = None
    sleep_time: str | None = None


# ==================== API Endpoints ====================

@app.get("/")
async def root():
    return {"status": "ok", "message": "AI Friend API is running 🤖"}


@app.post("/register", response_model=RegisterResponse)
async def register(req: RegisterRequest):
    """
    สมัครผู้ใช้ใหม่
    ส่ง: name, personality
    ได้: user_id สำหรับใช้แชท
    """
    user_id = str(uuid.uuid4())[:8]  # ID สั้น ๆ

    db.create_user(user_id, req.name, req.personality)
    db.update_user_field(user_id, "wake_time", req.wake_time)
    db.update_user_field(user_id, "sleep_time", req.sleep_time)

    # สร้างข้อความต้อนรับตามบุคลิก
    welcome_messages = {
        "friendly": f"เย้! ยินดีที่ได้รู้จัก {req.name}! เราชื่อฟ้า เป็นเพื่อนกันตั้งแต่วันนี้เลยนะ 😊",
        "caring": f"สวัสดีค่ะ {req.name} ฟ้ายินดีที่ได้รู้จักนะคะ จะคอยดูแลเป็นเพื่อนให้ค่ะ 💕",
        "cheerful": f"ว้าว! {req.name}! ยินดีที่ได้เจอกัน! ฟ้าตื่นเต้นมากเลย เราจะสนุกด้วยกันแน่ ๆ! 🎉",
        "professional": f"สวัสดีครับ {req.name} ผมชื่อฟ้า ยินดีที่ได้รู้จักครับ จะช่วยจัดการตารางและเตือนกิจวัตรให้ครับ 📋",
    }

    return RegisterResponse(
        user_id=user_id,
        name=req.name,
        personality=req.personality,
        message=welcome_messages.get(req.personality, welcome_messages["friendly"]),
    )


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """
    แชทกับ AI เพื่อน
    ส่ง: user_id + message
    ได้: reply + reminder (ถ้ามี)

    ระบบ 2 ชั้น:
    1. ลอง local reply ก่อน (ฟรี)
    2. ถ้าตอบไม่ได้ → ส่งไป Claude Haiku
    """
    logger = logging.getLogger(__name__)

    # ดึงข้อมูลผู้ใช้
    user = db.get_user(req.user_id)
    if not user:
        logger.warning(f"User not found: {req.user_id}")
        raise HTTPException(status_code=404, detail="User not found. Please register first.")

    user_name = user["name"]
    personality = user["personality"]

    try:
        memory = json.loads(user["memory"]) if isinstance(user["memory"], str) else user["memory"]
        if memory is None:
            memory = {}
    except (json.JSONDecodeError, TypeError):
        logger.warning(f"Bad memory JSON for user {req.user_id}, resetting")
        memory = {}

    # บันทึกข้อความผู้ใช้
    try:
        db.save_message(req.user_id, "user", req.message)
    except Exception as e:
        logger.error(f"Failed to save user message: {e}")

    try:
        # ========== รวบรวม Full Context (ข้อมูลทั้งหมดของผู้ใช้) ==========
        today_str = date.today().isoformat()
        mood_history = db.get_mood_history(req.user_id, days=7)
        routines = db.get_routines(req.user_id)
        pending_reminders = db.get_pending_reminders(req.user_id)
        stats = db.get_user_stats(req.user_id)

        routine_status = []
        for r in routines:
            done = db.is_routine_done_today(r["id"], today_str)
            routine_status.append({
                "title": r["title"],
                "time": r.get("time", ""),
                "done": done,
                "points": r["points"],
            })

        user_context = {
            "wake_time": user.get("wake_time", "07:00"),
            "sleep_time": user.get("sleep_time", "23:00"),
            "mood_history": mood_history,
            "routine_status": routine_status,
            "pending_reminders": [dict(r) for r in pending_reminders],
            "streak": stats.get("streak", 0),
            "total_points": stats.get("total_points", 0),
        }

        # ========== ชั้น 1: Local Reply (ฟรี) + Context-Aware ==========
        local_reply = try_local_reply(req.message, user_name, user_context)
        if local_reply:
            db.save_message(req.user_id, "assistant", local_reply)
            logger.info(f"Local reply for '{user_name}': {local_reply[:50]}")
            return ChatResponse(reply=local_reply)

        # ========== ชั้น 2: Claude Haiku + Full Context ==========
        recent_messages = db.get_recent_messages(req.user_id, limit=6)
        ai_result = await call_haiku(
            message=req.message,
            user_name=user_name,
            personality=personality,
            memory=memory,
            recent_messages=recent_messages,
            user_context=user_context,
        )

        reply = ai_result["reply"]

        # บันทึกคำตอบ AI
        db.save_message(req.user_id, "assistant", reply)

        # ========== จัดการ Memory ==========
        if ai_result["memory_update"]:
            process_memory_update(req.user_id, ai_result["memory_update"])

        # ========== จัดการ Reminder ==========
        response = ChatResponse(reply=reply)

        if ai_result["reminder"]:
            parsed = parse_reminder_text(ai_result["reminder"])
            if parsed:
                db.add_reminder(req.user_id, parsed["message"], parsed["remind_at"])
                response.has_reminder = True
                response.reminder_message = parsed["message"]
                response.reminder_time = parsed["remind_at"]

        return response

    except Exception as e:
        logger.error(f"Chat error for user '{user_name}' ({req.user_id}): {e}", exc_info=True)
        # Fallback: ลอง local reply อย่างเดียว (ไม่ต้อง context)
        try:
            local = try_local_reply(req.message, user_name)
            if local:
                return ChatResponse(reply=local)
        except Exception:
            pass
        return ChatResponse(
            reply=f"ขอโทษนะ {user_name} ฟ้ามีปัญหาชั่วคราว ลองใหม่อีกทีนะ~ 😅"
        )


@app.get("/reminders/{user_id}", response_model=list[ReminderItem])
async def get_reminders(user_id: str):
    """ดึง reminder ที่ยังไม่เสร็จ"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    reminders = db.get_pending_reminders(user_id)
    return [
        ReminderItem(
            id=r["id"],
            message=r["message"],
            remind_at=r["remind_at"],
            done=bool(r["done"]),
        )
        for r in reminders
    ]


@app.get("/memory/{user_id}")
async def get_memory(user_id: str):
    """ดึง memory ทั้งหมด (สำหรับ debug หรือแสดงในแอป)"""
    memory = get_memory_summary(user_id)
    if not memory:
        raise HTTPException(status_code=404, detail="User not found")
    return memory


@app.post("/reminders/{reminder_id}/done")
async def complete_reminder(reminder_id: int):
    """ทำเครื่องหมาย reminder ว่าเสร็จแล้ว"""
    db.mark_reminder_done(reminder_id)
    return {"status": "ok"}


# ==================== Health Check ====================

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
    }


@app.get("/debug/test-ai")
async def debug_test_ai():
    """ทดสอบ Anthropic API key — เรียกด้วย message ง่ายๆ"""
    import httpx as _httpx
    from ai_brain import ANTHROPIC_API_KEY, MODEL, API_URL

    if not ANTHROPIC_API_KEY:
        return {"status": "error", "detail": "ANTHROPIC_API_KEY is not set"}

    try:
        async with _httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                API_URL,
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                },
                json={
                    "model": MODEL,
                    "max_tokens": 50,
                    "messages": [{"role": "user", "content": "Say hello in Thai"}],
                },
            )
        if resp.status_code == 200:
            data = resp.json()
            reply = data["content"][0]["text"]
            return {
                "status": "ok",
                "model": MODEL,
                "reply": reply,
                "api_key_prefix": ANTHROPIC_API_KEY[:8] + "...",
            }
        else:
            return {
                "status": "error",
                "http_status": resp.status_code,
                "detail": resp.text[:500],
                "api_key_prefix": ANTHROPIC_API_KEY[:8] + "...",
            }
    except Exception as e:
        return {"status": "error", "detail": str(e)}


@app.get("/debug/db-stats")
async def debug_db_stats():
    """ดูสถานะ Database — มี user กี่คน, message กี่ข้อความ"""
    conn = db.get_db()
    users = conn.execute("SELECT COUNT(*) as cnt FROM users").fetchone()["cnt"]
    messages = conn.execute("SELECT COUNT(*) as cnt FROM messages").fetchone()["cnt"]
    conn.close()
    return {
        "status": "ok",
        "users": users,
        "messages": messages,
        "db_path": str(db.DB_PATH),
        "db_exists": db.DB_PATH.exists(),
    }


# ==================== Phase 2: Mood Tracker ====================

@app.post("/mood")
async def add_mood(req: MoodRequest):
    """บันทึกอารมณ์ประจำวัน (1-5)"""
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not 1 <= req.score <= 5:
        raise HTTPException(status_code=400, detail="Score must be 1-5")

    db.save_mood(req.user_id, req.score, req.note)
    return {"status": "ok", "message": "Mood saved"}


@app.get("/mood/{user_id}")
async def get_mood_history(user_id: str, days: int = 7):
    """ดึงประวัติอารมณ์ย้อนหลัง"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    moods = db.get_mood_history(user_id, days)
    return moods


# ==================== Phase 2: Routines ====================

@app.get("/routines/{user_id}")
async def get_routines(user_id: str):
    """ดึงรายการกิจวัตรทั้งหมด"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    routines = db.get_routines(user_id)
    today = date.today().isoformat()
    result = []
    for r in routines:
        done_today = db.is_routine_done_today(r["id"], today)
        result.append({
            "id": r["id"],
            "title": r["title"],
            "time": r["time"],
            "points": r["points"],
            "done_today": done_today,
        })
    return result


@app.post("/routines")
async def create_routine(req: RoutineRequest):
    """สร้างกิจวัตรใหม่"""
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    routine_id = db.create_routine(req.user_id, req.title, req.time, req.points)
    return {"status": "ok", "id": routine_id}


@app.post("/routines/{routine_id}/complete")
async def complete_routine(routine_id: int):
    """เช็คกิจวัตรว่าทำแล้ววันนี้"""
    today = date.today().isoformat()
    points = db.complete_routine(routine_id, today)
    return {"status": "ok", "points_earned": points}


@app.delete("/routines/{routine_id}")
async def delete_routine(routine_id: int):
    """ลบกิจวัตร"""
    db.delete_routine(routine_id)
    return {"status": "ok"}


# ==================== Phase 2: Stats ====================

@app.get("/stats/{user_id}")
async def get_user_stats(user_id: str):
    """ดึงสถิติ: streak, total points"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    stats = db.get_user_stats(user_id)
    return stats


# ==================== Phase 2: Settings ====================

@app.put("/settings")
async def update_settings(req: SettingsRequest):
    """อัพเดทการตั้งค่า"""
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if req.personality:
        db.update_user_field(req.user_id, "personality", req.personality)
    if req.wake_time:
        db.update_user_field(req.user_id, "wake_time", req.wake_time)
    if req.sleep_time:
        db.update_user_field(req.user_id, "sleep_time", req.sleep_time)

    return {"status": "ok"}


# ==================== Phase 2: Morning Brief / Night Wrap ====================

@app.get("/brief/morning/{user_id}")
async def morning_brief(user_id: str):
    """สร้างข้อความสรุปเช้า"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    reminders = db.get_pending_reminders(user_id)
    routines = db.get_routines(user_id)
    brief = generate_morning_brief(user["name"], reminders, routines)
    return {"message": brief}


@app.get("/brief/night/{user_id}")
async def night_wrap(user_id: str):
    """สร้างข้อความสรุปก่อนนอน"""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    today = date.today().isoformat()
    routines = db.get_routines(user_id)
    done_count = sum(1 for r in routines if db.is_routine_done_today(r["id"], today))
    moods = db.get_mood_history(user_id, 1)
    stats = db.get_user_stats(user_id)

    wrap = generate_night_wrap(
        user_name=user["name"],
        total_routines=len(routines),
        done_count=done_count,
        mood_today=moods[0] if moods else None,
        streak=stats.get("streak", 0),
    )
    return {"message": wrap}


# ==================== Alerts: Real-time Earthquake + News ====================

@app.get("/alerts", response_model=list[AlertItem])
async def get_alerts(severity: str | None = None, limit: int = 20):
    """ดึง alerts ทั้งหมดที่ยังไม่หมดอายุ (กรอง severity ได้)"""
    alerts = db.get_active_alerts(severity=severity, limit=limit)
    return [
        AlertItem(
            id=a["id"],
            alert_type=a["alert_type"],
            severity=a["severity"],
            title=a["title"],
            description=a["description"],
            source=a.get("source", ""),
            magnitude=a.get("magnitude", 0.0),
            location=a.get("location", ""),
            url=a.get("url", ""),
            fetched_at=a.get("fetched_at", ""),
        )
        for a in alerts
    ]


@app.get("/alerts/critical-summary")
async def critical_summary(hours: int = 6):
    """สรุป critical alerts ใน X ชั่วโมงล่าสุด (ใช้แสดง banner)"""
    alerts = db.get_latest_critical_alerts(hours_back=hours)
    return {
        "count": len(alerts),
        "alerts": [
            {
                "title": a["title"],
                "description": a["description"],
                "severity": a["severity"],
                "source": a.get("source", ""),
                "url": a.get("url", ""),
                "fetched_at": a.get("fetched_at", ""),
            }
            for a in alerts
        ],
    }


@app.post("/alerts/refresh")
async def refresh_alerts():
    """เรียก fetch alerts ทันที (manual trigger)"""
    try:
        await run_alert_fetch_job()
        alerts = db.get_active_alerts(limit=5)
        return {
            "status": "ok",
            "message": "Alerts refreshed",
            "active_count": len(alerts),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Refresh failed: {str(e)}")


# ==================== TTS: Microsoft Edge Neural TTS ====================

# เสียง Neural ภาษาไทย — เหมือน Siri/Google Assistant
TTS_VOICE = "th-TH-PremwadeeNeural"  # ผู้หญิง เสียงนุ่มเป็นธรรมชาติ
# ทางเลือก: "th-TH-NiwatNeural" (ผู้ชาย)


def _clean_text_for_tts(text: str) -> str:
    """ลบ emoji และอักขระพิเศษก่อนส่งให้ TTS"""
    emoji_pattern = re.compile(
        "["
        "\U0001F600-\U0001F64F"
        "\U0001F300-\U0001F5FF"
        "\U0001F680-\U0001F6FF"
        "\U0001F1E0-\U0001F1FF"
        "\U00002600-\U000026FF"
        "\U00002700-\U000027BF"
        "\U0000FE00-\U0000FE0F"
        "\U0001F900-\U0001F9FF"
        "\U0000200D"
        "\U000020E3"
        "]+",
        flags=re.UNICODE,
    )
    cleaned = emoji_pattern.sub("", text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    cleaned = cleaned.replace("~", "")
    return cleaned


class TtsRequest(BaseModel):
    text: str


@app.get("/tts")
async def text_to_speech_get(text: str = Query(..., min_length=1, max_length=500)):
    """GET endpoint (backward compatible)"""
    return await _generate_tts(text)


@app.post("/tts")
async def text_to_speech_post(req: TtsRequest):
    """POST endpoint — รองรับข้อความยาว"""
    return await _generate_tts(req.text)


async def _generate_tts(text: str):
    """แปลงข้อความเป็นเสียงไทย Neural (Microsoft Edge TTS) — เสียงเหมือนคนจริง"""
    cleaned = _clean_text_for_tts(text)
    if not cleaned:
        raise HTTPException(status_code=400, detail="No speakable text")

    if len(cleaned) > 1000:
        cleaned = cleaned[:1000]

    try:
        communicate = edge_tts.Communicate(cleaned, TTS_VOICE)
        audio_buffer = io.BytesIO()

        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_buffer.write(chunk["data"])

        audio_buffer.seek(0)

        if audio_buffer.getbuffer().nbytes < 100:
            raise HTTPException(status_code=500, detail="TTS produced empty audio")

        return StreamingResponse(
            audio_buffer,
            media_type="audio/mpeg",
            headers={"Cache-Control": "public, max-age=3600"},
        )
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"TTS error: {e}")
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")


# ==================== Phase 2: Social Login (เตรียมไว้) ====================

class SocialLoginRequest(BaseModel):
    provider: str          # 'google' หรือ 'apple'
    token: str             # ID token จาก provider
    name: str = ""
    email: str = ""
    photo_url: str = ""
    device_user_id: str = ""  # ถ้ามี → ลิงค์กับ account เดิม


@app.post("/auth/social")
async def social_login(req: SocialLoginRequest):
    """
    Phase 2: Login ด้วย Google/Apple
    - ถ้ามี device_user_id → ลิงค์ข้อมูลเดิมกับ social account
    - ถ้าไม่มี → สร้าง user ใหม่
    - ถ้าเคย login แล้ว → return user เดิม
    
    TODO: เพิ่ม token verification กับ Google/Apple
    """
    # ตอนนี้ return placeholder
    # เมื่อพร้อมจะเพิ่ม:
    # 1. Verify token กับ Google/Apple
    # 2. หา user จาก email
    # 3. ลิงค์กับ device_user_id ถ้ามี
    # 4. Return user + auth token

    return {
        "status": "not_implemented",
        "message": "Social login จะเปิดใช้ใน Phase 2",
    }
