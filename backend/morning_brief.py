"""
morning_brief.py — สร้างข้อความสรุปเช้าและก่อนนอน
ไม่ต้องเรียก LLM → ประหยัดค่าใช้จ่าย
"""

from datetime import datetime

DAY_NAMES = ["จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์", "อาทิตย์"]

MORNING_GREETINGS = [
    "อรุณสวัสดิ์",
    "สวัสดีตอนเช้า",
    "ตื่นแล้วเหรอ เก่งมาก",
]

NIGHT_GREETINGS = [
    "สรุปวันนี้ให้นะ",
    "วันนี้ผ่านไปแล้ว มาดูกันว่าทำอะไรได้บ้าง",
]

ENCOURAGEMENTS = [
    "วันนี้จะเป็นวันที่ดีนะ!",
    "สู้ ๆ นะวันนี้!",
    "พร้อมลุยวันใหม่กันเลย!",
    "ทำได้แน่นอน!",
]


def generate_morning_brief(
    user_name: str,
    reminders: list[dict],
    routines: list[dict],
) -> str:
    """สร้างข้อความสรุปเช้า"""
    now = datetime.now()
    day_name = DAY_NAMES[now.weekday()]
    date_str = now.strftime("%d/%m/%Y")

    import random
    greeting = random.choice(MORNING_GREETINGS)
    encourage = random.choice(ENCOURAGEMENTS)

    lines = [f"☀️ {greeting} {user_name}!"]
    lines.append(f"วัน{day_name}ที่ {date_str}")
    lines.append("")

    # แสดง reminders วันนี้
    today_str = now.strftime("%Y-%m-%d")
    today_reminders = [r for r in reminders if r.get("remind_at", "").startswith(today_str)]
    if today_reminders:
        lines.append("📋 นัดหมายวันนี้:")
        for r in today_reminders:
            time_part = r["remind_at"].split(" ")[-1] if " " in r["remind_at"] else ""
            lines.append(f"  • {time_part} {r['message']}")
        lines.append("")

    # แสดง routines
    if routines:
        lines.append("✅ กิจวัตรวันนี้:")
        for r in routines:
            time_str = f" ({r['time']})" if r.get("time") else ""
            lines.append(f"  ☐ {r['title']}{time_str}")
        lines.append("")

    lines.append(encourage)
    return "\n".join(lines)


def generate_night_wrap(
    user_name: str,
    total_routines: int,
    done_count: int,
    mood_today: dict | None,
    streak: int,
) -> str:
    """สร้างข้อความสรุปก่อนนอน"""
    import random
    greeting = random.choice(NIGHT_GREETINGS)

    lines = [f"🌙 {greeting} {user_name}~"]
    lines.append("")

    # สรุปกิจวัตร
    if total_routines > 0:
        percentage = int((done_count / total_routines) * 100)
        lines.append(f"📋 กิจวัตร: ทำได้ {done_count}/{total_routines} ({percentage}%)")
        if percentage == 100:
            lines.append("  🎉 ทำครบหมดเลย! เก่งมาก!")
        elif percentage >= 50:
            lines.append("  👍 ทำได้เกินครึ่ง ดีมาก!")
        else:
            lines.append("  💪 พรุ่งนี้ลองทำให้ได้มากขึ้นนะ!")

    # Streak
    if streak > 0:
        lines.append(f"🔥 Streak: {streak} วันติดต่อกัน!")

    # อารมณ์
    if mood_today:
        mood_emojis = {1: "😢", 2: "😔", 3: "😐", 4: "🙂", 5: "😊"}
        score = mood_today.get("score", 3)
        emoji = mood_emojis.get(score, "😐")
        lines.append(f"💭 อารมณ์วันนี้: {emoji}")

    lines.append("")
    lines.append("ฝันดีนะ~ 🌟")
    return "\n".join(lines)
