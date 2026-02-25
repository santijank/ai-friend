"""
memory.py — Memory Manager (Enhanced)
รับ memory_update จาก AI แล้วอัพเดทเข้า memory ของผู้ใช้อัตโนมัติ
ดึงข้อมูลสำคัญ 8 หมวด: อาชีพ, อารมณ์, คนรัก, ความสนใจ, เป้าหมาย, ครอบครัว, สุขภาพ, เหตุการณ์สำคัญ
"""

import re
import json
from datetime import datetime
from database import get_user, update_user_memory


def process_memory_update(user_id: str, memory_update_text: str):
    """
    รับข้อความ memory_update จาก AI แล้วเพิ่มเข้า memory
    เก็บเป็น facts + ดึง structured data อัตโนมัติ
    """
    if not memory_update_text:
        return

    user = get_user(user_id)
    if not user:
        return

    memory = json.loads(user["memory"]) if isinstance(user["memory"], str) else user["memory"]

    # เพิ่มเป็น fact ใหม่
    if "facts" not in memory:
        memory["facts"] = []

    # ไม่เก็บ fact ซ้ำ
    if memory_update_text not in memory["facts"]:
        memory["facts"].append(memory_update_text)

    # จำกัดแค่ 20 facts ล่าสุด
    if len(memory["facts"]) > 20:
        memory["facts"] = memory["facts"][-20:]

    # ดึงข้อมูลสำคัญออกมาเก็บแยก (8 หมวด)
    _extract_key_info(memory, memory_update_text)

    update_user_memory(user_id, memory)


def _extract_key_info(memory: dict, text: str):
    """ดึงข้อมูลสำคัญจาก fact เก็บแยก — 8 หมวด"""
    text_lower = text.lower()

    # 1. อาชีพ / การศึกษา
    job_keywords = [
        "ทำงาน", "อาชีพ", "เป็นพนักงาน", "ทำเป็น",
        "นักเรียน", "นักศึกษา", "เรียนอยู่", "เรียนที่",
        "ทำธุรกิจ", "เปิดร้าน", "ฟรีแลนซ์",
    ]
    for kw in job_keywords:
        if kw in text_lower:
            memory["job"] = text
            break

    # 2. อารมณ์ล่าสุด
    mood_keywords = {
        "เครียด": "เครียด", "เหนื่อย": "เหนื่อย", "เศร้า": "เศร้า",
        "ดีใจ": "ดีใจ", "มีความสุข": "มีความสุข", "สนุก": "สนุก",
        "กังวล": "กังวล", "โกรธ": "โกรธ", "เบื่อ": "เบื่อ",
        "ตื่นเต้น": "ตื่นเต้น", "หดหู่": "หดหู่",
        "โดดเดี่ยว": "โดดเดี่ยว", "หงุดหงิด": "หงุดหงิด",
    }
    for kw, mood in mood_keywords.items():
        if kw in text_lower:
            memory["recent_mood"] = mood
            break

    # 3. คนสำคัญ / คนรัก
    partner_keywords = ["แฟน", "สามี", "ภรรยา", "คนรัก", "boyfriend", "girlfriend"]
    for kw in partner_keywords:
        if kw in text_lower:
            memory["partner"] = text
            break

    # 4. ความสนใจ / งานอดิเรก
    interest_keywords = [
        "ชอบ", "สนใจ", "หลงใหล", "โปรด", "ติดตาม",
        "เล่น", "ดู", "ฟัง", "อ่าน", "งานอดิเรก",
    ]
    for kw in interest_keywords:
        if kw in text_lower:
            if "interests" not in memory:
                memory["interests"] = []
            if text not in memory["interests"]:
                memory["interests"].append(text)
                if len(memory["interests"]) > 10:
                    memory["interests"] = memory["interests"][-10:]
            break

    # 5. เป้าหมาย / ความฝัน
    goal_keywords = [
        "อยากได้", "ตั้งใจ", "เป้าหมาย", "ฝัน", "อยากเป็น",
        "อยากทำ", "วางแผน", "อยากลอง", "ตั้งเป้า",
    ]
    for kw in goal_keywords:
        if kw in text_lower:
            if "goals" not in memory:
                memory["goals"] = []
            if text not in memory["goals"]:
                memory["goals"].append(text)
                if len(memory["goals"]) > 5:
                    memory["goals"] = memory["goals"][-5:]
            break

    # 6. ครอบครัว
    family_keywords = [
        "แม่", "พ่อ", "น้อง", "พี่", "ลูก",
        "ปู่", "ย่า", "ตา", "ยาย", "พี่น้อง",
    ]
    for kw in family_keywords:
        if kw in text_lower:
            memory["family_mention"] = text
            break

    # 7. สุขภาพ
    health_keywords = [
        "ป่วย", "หมอ", "โรงพยาบาล", "ยา", "ออกกำลัง",
        "อาหาร", "นอนไม่หลับ", "ปวด", "แพ้", "ไข้",
    ]
    for kw in health_keywords:
        if kw in text_lower:
            memory["health_mention"] = text
            break

    # 8. เหตุการณ์สำคัญ (มีคำบอกเวลา)
    event_keywords = ["นัด", "ประชุม", "สอบ", "เดินทาง", "วันเกิด", "งานแต่ง", "สัมภาษณ์"]
    date_pattern = re.compile(
        r"\d{1,2}[/-]\d{1,2}|\bพรุ่งนี้\b|\bวันนี้\b|\bสัปดาห์หน้า\b|\bเดือนหน้า\b"
    )
    for kw in event_keywords:
        if kw in text_lower and date_pattern.search(text_lower):
            if "important_events" not in memory:
                memory["important_events"] = []
            event_entry = {
                "date": datetime.now().strftime("%Y-%m-%d"),
                "event": text,
            }
            memory["important_events"].append(event_entry)
            if len(memory["important_events"]) > 10:
                memory["important_events"] = memory["important_events"][-10:]
            break


def get_memory_summary(user_id: str) -> dict:
    """ดึง memory ทั้งหมดของผู้ใช้"""
    user = get_user(user_id)
    if not user:
        return {}
    return json.loads(user["memory"]) if isinstance(user["memory"], str) else user["memory"]
