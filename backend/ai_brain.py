"""
ai_brain.py — สมองของ AI เพื่อน (Enhanced)
จัดการ System Prompt, เรียก Claude Haiku, แยกผลลัพธ์
เพิ่ม: Smart Context Builder, Emotional Intelligence, Context-Aware Local Replies
"""

import os
import json
import re
import random
import logging
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx

import database as db

logger = logging.getLogger(__name__)

BKK = ZoneInfo("Asia/Bangkok")  # UTC+7

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
MODEL = "claude-haiku-4-5-20251001"
API_URL = "https://api.anthropic.com/v1/messages"

# Log API key status on import (masked)
if ANTHROPIC_API_KEY:
    logger.info(f"ANTHROPIC_API_KEY loaded: {ANTHROPIC_API_KEY[:8]}...{ANTHROPIC_API_KEY[-4:]}")
else:
    logger.error("ANTHROPIC_API_KEY is NOT set! Claude API will fail.")


# ==================== Smart Context Builder ====================

def _build_live_context(user_context: dict) -> str:
    """แปลง user_context -> ข้อความสรุปสั้น สำหรับ prompt (ประหยัด token)"""
    if not user_context:
        return ""

    parts = []
    now = datetime.now(BKK)

    # 1. ตารางเวลา
    wake = user_context.get("wake_time", "07:00")
    sleep = user_context.get("sleep_time", "23:00")
    parts.append(f"ตื่น {wake} | นอน {sleep}")

    # 2. อารมณ์ล่าสุด + แนวโน้ม
    moods = user_context.get("mood_history", [])
    if moods:
        scores = [m["score"] for m in moods]
        avg = sum(scores) / len(scores)
        latest = scores[-1]

        trend = ""
        if len(scores) >= 3:
            if scores[-1] < scores[-3]:
                trend = " (แนวโน้มลดลง)"
            elif scores[-1] > scores[-3]:
                trend = " (แนวโน้มดีขึ้น)"

        mood_labels = {1: "แย่มาก", 2: "ไม่ค่อยดี", 3: "เฉย ๆ", 4: "ดี", 5: "ดีมาก"}
        latest_label = mood_labels.get(latest, "เฉย ๆ")
        parts.append(f"อารมณ์ล่าสุด: {latest_label}{trend} (เฉลี่ย {avg:.1f}/5 ใน {len(scores)} วัน)")

    # 3. กิจวัตรวันนี้
    routines = user_context.get("routine_status", [])
    if routines:
        done = sum(1 for r in routines if r["done"])
        total = len(routines)
        undone = [r["title"] for r in routines if not r["done"]]
        parts.append(f"กิจวัตรวันนี้: {done}/{total} เสร็จ")
        if undone and done < total:
            parts.append(f"ยังไม่ทำ: {', '.join(undone[:3])}")

    # 4. นัดหมายวันนี้
    reminders = user_context.get("pending_reminders", [])
    today_str = now.strftime("%Y-%m-%d")
    today_reminders = [r for r in reminders if r.get("remind_at", "").startswith(today_str)]
    if today_reminders:
        msgs = [r["message"] for r in today_reminders[:2]]
        parts.append(f"นัดวันนี้: {', '.join(msgs)}")
    elif reminders:
        next_rem = reminders[0]
        parts.append(f"นัดถัดไป: {next_rem['message']} ({next_rem.get('remind_at', '')})")

    # 5. Streak (แสดงเฉพาะถ้า >= 2 วัน)
    streak = user_context.get("streak", 0)
    total_points = user_context.get("total_points", 0)
    if streak >= 2:
        parts.append(f"Streak: {streak} วันติดต่อกัน ({total_points} points)")

    # 6. เตือนภัย / ข่าวด่วน (ดึงจาก DB ตรง)
    try:
        critical_alerts = db.get_latest_critical_alerts(hours_back=6)
        if critical_alerts:
            alert_lines = []
            for a in critical_alerts[:3]:
                alert_lines.append(f"[{a['severity'].upper()}] {a['title']}")
            parts.append("ข่าวด่วน:\n" + "\n".join(alert_lines))
    except Exception:
        pass

    return "\n".join(parts) if parts else ""


# ==================== System Prompt ====================

def build_system_prompt(
    user_name: str,
    personality: str,
    memory: dict,
    user_context: dict | None = None,
) -> str:
    """สร้าง System Prompt ที่ฉลาด — รวม memory + live context + emotional tone"""

    personality_styles = {
        "friendly": "เป็นเพื่อนสนิท พูดเป็นกันเอง สนุกสนาน ใช้ภาษาไม่เป็นทางการ",
        "caring": "เป็นพี่สาวที่อบอุ่น ห่วงใย พูดนุ่มนวล คอยดูแล",
        "cheerful": "เป็นน้องร่าเริง สดใส ให้กำลังใจเก่ง พลังบวก",
        "professional": "เป็นพี่เลี้ยงที่สุภาพ จัดระเบียบดี พูดชัดเจน",
    }

    style = personality_styles.get(personality, personality_styles["friendly"])
    memory_text = _summarize_memory(memory)
    live_context = _build_live_context(user_context) if user_context else ""

    today = datetime.now(BKK)
    day_names = ["จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์", "อาทิตย์"]
    day_name = day_names[today.weekday()]
    time_str = today.strftime("%H:%M")
    hour = today.hour

    if 5 <= hour < 12:
        time_context = "ตอนเช้า"
    elif 12 <= hour < 17:
        time_context = "ตอนบ่าย"
    elif 17 <= hour < 21:
        time_context = "ตอนเย็น"
    else:
        time_context = "ตอนกลางคืน"

    # Emotional Intelligence — ปรับ tone ตามอารมณ์
    tone_hint = ""
    if user_context:
        moods = user_context.get("mood_history", [])
        if moods:
            latest_score = moods[-1]["score"]
            if latest_score <= 2:
                tone_hint = "\n- อารมณ์ผู้ใช้ไม่ค่อยดี -> ตอบด้วยความเห็นอกเห็นใจ รับฟังก่อน อย่าเพิ่งแนะนำ"
            elif latest_score >= 4:
                tone_hint = "\n- อารมณ์ผู้ใช้ดี -> ร่วมยินดี ตอบสนุก มีพลัง"

    live_section = ""
    if live_context:
        live_section = f"\nสถานการณ์ตอนนี้:\n{live_context}\n"

    return f"""คุณชื่อ "ฟ้า" {style}

ผู้ใช้ชื่อ: {user_name}
วันนี้: วัน{day_name} เวลา {time_str} ({time_context})
{live_section}
ข้อมูลที่รู้เกี่ยวกับ {user_name}:
{memory_text}

กฎสำคัญ:
- ตอบสั้น ๆ 1-3 ประโยค เหมือนแชทกับเพื่อน
- ใช้ชื่อ {user_name} บ้าง
- ใส่ emoji บ้างแต่ไม่เยอะ
- ถ้าเขาเล่าปัญหา -> รับฟังก่อน อย่าเพิ่งแนะนำ
- ถ้าเขาบอกนัดหรือสิ่งที่ต้องทำ -> จดและเตือนให้
- ถ้ากิจวัตรยังไม่ครบ -> ทักเตือนเบา ๆ ถ้าเหมาะกับบทสนทนา
- อ้างอิงสิ่งที่รู้เกี่ยวกับผู้ใช้ เพื่อให้รู้สึกว่าจำเขาได้
- ถ้ามีข่าวด่วน/เตือนภัย -> แจ้งผู้ใช้แบบห่วงใย เช่น "ฟ้าเพิ่งเห็นข่าวว่า..." อย่าตกใจผู้ใช้{tone_hint}

ตอบในรูปแบบนี้เสมอ:
REPLY: (ข้อความถึงผู้ใช้)
MEMORY_UPDATE: (ข้อมูลใหม่ที่ได้เรียนรู้จากบทสนทนานี้ เขียนสั้น ๆ | หรือ NONE)
REMINDER: (YYYY-MM-DD HH:MM ข้อความเตือน | หรือ NONE)

ตัวอย่าง REMINDER ที่ถูกต้อง:
- ผู้ใช้: "เตือนตอน 3 โมง ไปหาหมอ" → REMINDER: {time_str[:10]} 15:00 ไปหาหมอ
- ผู้ใช้: "พรุ่งนี้ 8 โมง ประชุม" → REMINDER: (วันพรุ่งนี้ YYYY-MM-DD) 08:00 ประชุม
- ไม่มีนัด → REMINDER: NONE
สำคัญ: REMINDER ต้องเป็นรูปแบบ YYYY-MM-DD HH:MM ข้อความ เท่านั้น ห้ามใส่คำอื่นนำหน้าวันที่"""


def _summarize_memory(memory: dict) -> str:
    """แปลง memory dict -> ข้อความสั้น ๆ สำหรับ prompt"""
    parts = []
    if memory.get("name"):
        parts.append(f"ชื่อ: {memory['name']}")
    if memory.get("job"):
        parts.append(f"อาชีพ: {memory['job']}")
    if memory.get("interests"):
        parts.append(f"สนใจ: {', '.join(memory['interests'][-5:])}")
    if memory.get("goals"):
        parts.append(f"เป้าหมาย: {', '.join(memory['goals'][-3:])}")
    if memory.get("partner"):
        parts.append(f"คนสำคัญ: {memory['partner']}")
    if memory.get("family_mention"):
        parts.append(f"ครอบครัว: {memory['family_mention']}")
    if memory.get("health_mention"):
        parts.append(f"สุขภาพ: {memory['health_mention']}")
    if memory.get("facts"):
        for fact in memory["facts"][-5:]:
            parts.append(f"- {fact}")
    if memory.get("recent_mood"):
        parts.append(f"อารมณ์ล่าสุด: {memory['recent_mood']}")
    if memory.get("important_events"):
        for evt in memory["important_events"][-3:]:
            parts.append(f"- {evt.get('date', '')}: {evt.get('event', '')}")

    return "\n".join(parts) if parts else "ยังไม่มีข้อมูล (เพิ่งรู้จักกัน)"


# ==================== Local Quick Replies (ฟรี 100%) ====================

QUICK_REPLIES = {
    "greetings": {
        "triggers": ["สวัสดี", "หวัดดี", "ดีจ้า", "ดีครับ", "ดีค่ะ", "hi", "hello", "hey"],
        "replies": [
            "หวัดดี {name}~ วันนี้เป็นไงบ้าง? 😊",
            "มาแล้ว! {name} สบายดีมั้ย?",
            "ดีจ้า {name}~ มีอะไรเล่าให้ฟังมั้ย?",
            "โย่ {name}! วันนี้ทำอะไรอยู่เอ่ย?",
        ],
    },
    "thanks": {
        "triggers": ["ขอบคุณ", "ขอบใจ", "thank", "thanks"],
        "replies": [
            "ไม่เป็นไร~ เพื่อนกันนี่นา 😄",
            "ยินดีเสมอ {name}! 💕",
            "เรื่องเล็ก ๆ ไม่ต้องขอบคุณหรอก~",
        ],
    },
    "goodnight": {
        "triggers": ["ราตรีสวัสดิ์", "ฝันดี", "นอนแล้ว", "นอนก่อน", "good night"],
        "replies": [
            "ฝันดีนะ {name} 🌙 พรุ่งนี้เจอกัน!",
            "ราตรีสวัสดิ์~ นอนหลับให้สบายเลยนะ ✨",
            "ไปพักผ่อนเลย {name} เดี๋ยวเช้ามาคุยกันใหม่ 😴",
        ],
    },
    "goodmorning": {
        "triggers": ["อรุณสวัสดิ์", "ตื่นแล้ว", "good morning"],
        "replies": [
            "อรุณสวัสดิ์ {name}~ ☀️ วันนี้จะเป็นวันที่ดีนะ!",
            "ตื่นแล้วเหรอ! เก่งมาก {name} 💪",
            "เช้าแล้ว~ {name} กินข้าวเช้าด้วยนะ 🍳",
        ],
    },
    "how_are_you": {
        "triggers": ["เป็นไง", "สบายดีมั้ย", "ทำอะไรอยู่"],
        "replies": [
            "ฟ้าสบายดี~ รอ {name} ทักมาอยู่เลย 😊",
            "ดีจ้า! {name} ล่ะ เป็นไงบ้าง?",
        ],
    },
    "tired": {
        "triggers": ["เหนื่อย", "ล้า", "ไม่ไหวแล้ว", "หมดแรง", "อ่อนเพลีย"],
        "replies": [
            "เหนื่อยก็พักก่อนนะ {name} 🥺 ร่างกายสำคัญ",
            "อย่าฝืนมากเกินไปนะ {name}~ หายใจลึก ๆ ก่อน",
            "รู้สึกอย่างนั้นได้เลย เหนื่อยก็บอกได้นะ 💕",
        ],
    },
    "stressed": {
        "triggers": ["เครียด", "กดดัน", "stress", "เครียดมาก"],
        "replies": [
            "เครียดมั้ยเนี่ย... {name} หายใจลึก ๆ ก่อนนะ 🌬️",
            "เครียดเหรอ~ อยากเล่าให้ฟังมั้ย? ฟ้าอยู่ตรงนี้",
            "เข้าใจเลย เครียดแบบนี้ไม่ง่ายเลย ฟ้าฟังอยู่นะ 😔",
        ],
    },
    "sad": {
        "triggers": ["เศร้า", "ร้องไห้", "ใจหาย", "เสียใจ", "หดหู่", "เหงา"],
        "replies": [
            "เศร้าเหรอ {name}... อยากคุยก็บอกนะ ฟ้าฟังอยู่ 💙",
            "ไม่เป็นไรนะ {name} ฟ้าอยู่ตรงนี้เสมอ",
            "ให้กำลังใจ {name} นะ เดี๋ยวทุกอย่างจะดีขึ้น 🤍",
        ],
    },
    "happy": {
        "triggers": ["ดีใจ", "มีความสุข", "เย้", "สนุก", "เฮ", "ยินดี"],
        "replies": [
            "ดีใจด้วย {name}! 🎉 เล่าให้ฟังได้เลยนะ",
            "โอ้ว {name} ดีใจมากเลย! เกิดอะไรขึ้น? 😊",
            "เย้ {name}! พลังงานบวกมาก~ ✨",
        ],
    },
    "eating": {
        "triggers": ["กินข้าว", "กินอะไร", "อิ่มแล้ว", "หิว", "กินมาแล้ว"],
        "replies": [
            "กินให้อิ่มด้วยนะ {name}~ ☺️",
            "กินอร่อยมั้ย {name}? อย่าลืมกินผักด้วยนะ 🥦",
            "หิวเหรอ? รีบไปกินเลย {name}~ 🍚",
        ],
    },
    "bored": {
        "triggers": ["เบื่อ", "ว่างมาก", "ไม่รู้จะทำอะไร", "น่าเบื่อ"],
        "replies": [
            "เบื่อเหรอ {name}~ มาคุยกันได้เลย 😄",
            "ว่างงั้นเหรอ! มีกิจวัตรที่ยังทำไม่ได้มั้ยนะ? 📋",
            "เบื่อก็มาเล่าเรื่องให้ฟังสิ {name}~ ฟ้าสนใจ",
        ],
    },
}


def try_local_reply(
    message: str,
    user_name: str,
    user_context: dict | None = None,
) -> str | None:
    """พยายามตอบจาก template ก่อน (ไม่เสียเงิน API) — Context-Aware"""
    msg_lower = message.strip().lower()

    for category, data in QUICK_REPLIES.items():
        for trigger in data["triggers"]:
            if trigger in msg_lower and len(msg_lower) < 40:
                reply = random.choice(data["replies"])
                result = reply.replace("{name}", user_name)

                # Context-aware: เบื่อ + มี routine ยังไม่ทำ
                if category == "bored" and user_context:
                    undone = [
                        r["title"] for r in user_context.get("routine_status", [])
                        if not r["done"]
                    ]
                    if undone:
                        result = f"เบื่อเหรอ {user_name}~ ยังมี '{undone[0]}' ที่ยังไม่ได้ทำนะ! 📋"

                # Context-aware: อรุณสวัสดิ์ + มีนัดวันนี้
                if category == "goodmorning" and user_context:
                    today_str = datetime.now(BKK).strftime("%Y-%m-%d")
                    today_rem = [
                        r["message"] for r in user_context.get("pending_reminders", [])
                        if r.get("remind_at", "").startswith(today_str)
                    ]
                    if today_rem:
                        result += f" วันนี้มีนัด: {today_rem[0]} ด้วยนะ! 📅"

                # Context-aware: ฝันดี + streak
                if category == "goodnight" and user_context:
                    streak = user_context.get("streak", 0)
                    if streak >= 3:
                        result += f" (Streak {streak} วันแล้ว! เก่งมาก 🔥)"

                return result
    return None


# ==================== Call Claude Haiku ====================

async def call_haiku(
    message: str,
    user_name: str,
    personality: str,
    memory: dict,
    recent_messages: list[dict],
    user_context: dict | None = None,
) -> dict:
    """เรียก Claude Haiku API — ได้ reply + memory_update + reminder"""

    system_prompt = build_system_prompt(user_name, personality, memory, user_context)

    # สร้าง messages array
    messages = []
    for msg in recent_messages:
        messages.append({
            "role": msg["role"],
            "content": msg["content"],
        })
    messages.append({"role": "user", "content": message})

    # เรียก API
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            API_URL,
            headers={
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": MODEL,
                "max_tokens": 500,  # เพิ่มจาก 300 -> ตอบได้ละเอียดขึ้น
                "system": system_prompt,
                "messages": messages,
            },
        )

    if response.status_code != 200:
        logger.error(
            f"Claude API error {response.status_code} for user '{user_name}': "
            f"{response.text[:500]}"
        )
        return {
            "reply": f"อุ๊ปส์ ฟ้าตอบไม่ได้ชั่วคราว ลองใหม่นะ {user_name}~ 😅",
            "memory_update": None,
            "reminder": None,
        }

    data = response.json()
    raw_text = data["content"][0]["text"]
    logger.info(f"Claude API success for '{user_name}', tokens: "
                f"in={data.get('usage', {}).get('input_tokens', '?')}, "
                f"out={data.get('usage', {}).get('output_tokens', '?')}")

    return parse_ai_response(raw_text)


def parse_ai_response(raw_text: str) -> dict:
    """แยกคำตอบ AI ออกเป็น reply, memory_update, reminder
    รองรับทั้งแบบมี REPLY: นำหน้า และไม่มี"""

    result = {
        "reply": "",
        "memory_update": None,
        "reminder": None,
    }

    # ดึง MEMORY_UPDATE
    mem_match = re.search(r"MEMORY_UPDATE:\s*(.+?)(?=REMINDER:|$)", raw_text, re.DOTALL)
    if mem_match:
        mem_text = mem_match.group(1).strip()
        if mem_text.upper() != "NONE" and mem_text:
            result["memory_update"] = mem_text

    # ดึง REMINDER
    rem_match = re.search(r"REMINDER:\s*(.+?)$", raw_text, re.DOTALL)
    if rem_match:
        rem_text = rem_match.group(1).strip()
        if rem_text.upper() != "NONE" and rem_text:
            result["reminder"] = rem_text

    # ดึง REPLY — ลอง REPLY: ก่อน, ถ้าไม่มีก็ตัด MEMORY_UPDATE/REMINDER ออก
    reply_match = re.search(r"REPLY:\s*(.+?)(?=MEMORY_UPDATE:|REMINDER:|$)", raw_text, re.DOTALL)
    if reply_match:
        result["reply"] = reply_match.group(1).strip()
    else:
        # AI ไม่ได้ใส่ REPLY: → เอา raw text แล้วตัด tags ออก
        clean = raw_text
        clean = re.sub(r"MEMORY_UPDATE:.*?(?=REMINDER:|$)", "", clean, flags=re.DOTALL)
        clean = re.sub(r"REMINDER:.*$", "", clean, flags=re.DOTALL)
        result["reply"] = clean.strip()

    return result


def parse_reminder_text(reminder_text: str) -> dict | None:
    """แยก reminder text เป็น datetime + message
    รองรับหลายรูปแบบ:
      - 2025-03-01 14:30 ข้อความ
      - 2025-03-01T14:30 ข้อความ
      - 14:30 ข้อความ (ใช้วันนี้/พรุ่งนี้)
      - HH:MM ข้อความ
    """
    if not reminder_text:
        return None

    text = reminder_text.strip()

    # Pattern 1: YYYY-MM-DD HH:MM ข้อความ (original)
    match = re.match(r"(\d{4}-\d{2}-\d{2})\s*[T\s]\s*(\d{1,2}:\d{2})\s+(.+)", text, re.DOTALL)
    if match:
        date_part = match.group(1)
        time_part = match.group(2)
        message = match.group(3).strip()
        return {
            "remind_at": f"{date_part} {time_part}",
            "message": message,
        }

    # Pattern 2: HH:MM ข้อความ (ไม่มีวันที่ → ใช้วันนี้/พรุ่งนี้)
    match = re.match(r"(\d{1,2}:\d{2})\s+(.+)", text, re.DOTALL)
    if match:
        time_str = match.group(1)
        message = match.group(2).strip()
        try:
            bkk = ZoneInfo("Asia/Bangkok")
            now = datetime.now(bkk)
            hour, minute = map(int, time_str.split(":"))
            target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if target <= now:
                target += timedelta(days=1)  # ถ้าเลยแล้ว → พรุ่งนี้
            date_part = target.strftime("%Y-%m-%d")
            return {
                "remind_at": f"{date_part} {time_str}",
                "message": message,
            }
        except Exception:
            pass

    # Pattern 3: พรุ่งนี้ HH:MM ข้อความ / วันนี้ HH:MM ข้อความ
    match = re.match(r"(วันนี้|พรุ่งนี้|tomorrow|today)\s*(\d{1,2}:\d{2})\s+(.+)", text, re.DOTALL | re.IGNORECASE)
    if match:
        day_word = match.group(1).lower()
        time_str = match.group(2)
        message = match.group(3).strip()
        try:
            bkk = ZoneInfo("Asia/Bangkok")
            now = datetime.now(bkk)
            hour, minute = map(int, time_str.split(":"))
            if day_word in ("พรุ่งนี้", "tomorrow"):
                target = (now + timedelta(days=1)).replace(hour=hour, minute=minute, second=0, microsecond=0)
            else:
                target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            date_part = target.strftime("%Y-%m-%d")
            return {
                "remind_at": f"{date_part} {time_str}",
                "message": message,
            }
        except Exception:
            pass

    return None
