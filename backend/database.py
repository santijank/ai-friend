"""
database.py — SQLite Database Manager
เก็บข้อมูลผู้ใช้ แชท memory reminder mood และ routine ทั้งหมดในไฟล์เดียว
"""

import sqlite3
import json
from datetime import datetime, date, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

BKK = ZoneInfo("Asia/Bangkok")

DB_PATH = Path("ai_friend.db")


def get_db():
    """สร้าง connection ไปยัง SQLite"""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")  # performance ดีขึ้น
    return conn


def init_db():
    """สร้างตารางทั้งหมด — เรียกตอน server เริ่ม"""
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            name TEXT DEFAULT '',
            personality TEXT DEFAULT 'friendly',
            memory TEXT DEFAULT '{}',
            wake_time TEXT DEFAULT '07:00',
            sleep_time TEXT DEFAULT '23:00',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            message TEXT NOT NULL,
            remind_at TIMESTAMP NOT NULL,
            done BOOLEAN DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_reminders_user ON reminders(user_id, remind_at);

        CREATE TABLE IF NOT EXISTS moods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            score INTEGER NOT NULL,
            note TEXT DEFAULT '',
            created_at DATE,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS routines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            time TEXT DEFAULT '',
            points INTEGER DEFAULT 5,
            active BOOLEAN DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS routine_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            routine_id INTEGER NOT NULL,
            completed_date DATE NOT NULL,
            points_earned INTEGER DEFAULT 0,
            FOREIGN KEY (routine_id) REFERENCES routines(id),
            UNIQUE(routine_id, completed_date)
        );

        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            alert_type TEXT NOT NULL,
            severity TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            source TEXT DEFAULT '',
            external_id TEXT DEFAULT '',
            magnitude REAL DEFAULT 0.0,
            location TEXT DEFAULT '',
            url TEXT DEFAULT '',
            fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP,
            is_active BOOLEAN DEFAULT 1,
            UNIQUE(external_id)
        );

        CREATE INDEX IF NOT EXISTS idx_moods_user ON moods(user_id, created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_routines_user ON routines(user_id);
        CREATE INDEX IF NOT EXISTS idx_routine_logs ON routine_logs(routine_id, completed_date);
        CREATE INDEX IF NOT EXISTS idx_alerts_active ON alerts(is_active, fetched_at DESC);
        CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity, is_active, fetched_at DESC);
    """)
    conn.commit()
    conn.close()


# ==================== User ====================

def create_user(user_id: str, name: str, personality: str = "friendly") -> dict:
    """สร้างผู้ใช้ใหม่"""
    conn = get_db()
    memory = json.dumps({
        "name": name,
        "interests": [],
        "goals": [],
        "important_events": [],
        "facts": []
    }, ensure_ascii=False)

    conn.execute(
        "INSERT OR IGNORE INTO users (id, name, personality, memory) VALUES (?, ?, ?, ?)",
        (user_id, name, personality, memory)
    )
    conn.commit()
    conn.close()
    return {"user_id": user_id, "name": name, "personality": personality}


def get_user(user_id: str) -> dict | None:
    """ดึงข้อมูลผู้ใช้"""
    conn = get_db()
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None


def update_user_memory(user_id: str, memory: dict):
    """อัพเดท memory ของผู้ใช้"""
    conn = get_db()
    conn.execute(
        "UPDATE users SET memory = ?, last_active = ? WHERE id = ?",
        (json.dumps(memory, ensure_ascii=False), datetime.now(BKK).isoformat(), user_id)
    )
    conn.commit()
    conn.close()


def update_user_field(user_id: str, field: str, value: str):
    """อัพเดทฟิลด์ใดฟิลด์หนึ่ง"""
    allowed_fields = {"name", "personality", "wake_time", "sleep_time"}
    if field not in allowed_fields:
        return
    conn = get_db()
    conn.execute(f"UPDATE users SET {field} = ? WHERE id = ?", (value, user_id))
    conn.commit()
    conn.close()


# ==================== Messages ====================

def save_message(user_id: str, role: str, content: str):
    """บันทึกข้อความ"""
    conn = get_db()
    conn.execute(
        "INSERT INTO messages (user_id, role, content) VALUES (?, ?, ?)",
        (user_id, role, content)
    )
    conn.commit()
    conn.close()


def get_recent_messages(user_id: str, limit: int = 6) -> list[dict]:
    """ดึงแชทล่าสุด (ส่งให้ AI เป็น context)"""
    conn = get_db()
    rows = conn.execute(
        "SELECT role, content, created_at FROM messages WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
        (user_id, limit)
    ).fetchall()
    conn.close()
    # reverse เพื่อให้เรียงจากเก่า → ใหม่
    return [dict(r) for r in reversed(rows)]


# ==================== Reminders ====================

def add_reminder(user_id: str, message: str, remind_at: str):
    """เพิ่ม reminder"""
    conn = get_db()
    conn.execute(
        "INSERT INTO reminders (user_id, message, remind_at) VALUES (?, ?, ?)",
        (user_id, message, remind_at)
    )
    conn.commit()
    conn.close()


def get_pending_reminders(user_id: str) -> list[dict]:
    """ดึง reminder ที่ยังไม่เสร็จ"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM reminders WHERE user_id = ? AND done = 0 ORDER BY remind_at",
        (user_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def mark_reminder_done(reminder_id: int):
    """ทำเครื่องหมายว่า reminder เสร็จแล้ว"""
    conn = get_db()
    conn.execute("UPDATE reminders SET done = 1 WHERE id = ?", (reminder_id,))
    conn.commit()
    conn.close()


# ==================== Moods ====================

def save_mood(user_id: str, score: int, note: str = ""):
    """บันทึกอารมณ์ (แทนที่ค่าเดิมถ้าบันทึกวันเดียวกัน)"""
    conn = get_db()
    today = datetime.now(BKK).date().isoformat()
    existing = conn.execute(
        "SELECT id FROM moods WHERE user_id = ? AND created_at = ?",
        (user_id, today)
    ).fetchone()

    if existing:
        conn.execute(
            "UPDATE moods SET score = ?, note = ? WHERE id = ?",
            (score, note, existing["id"])
        )
    else:
        conn.execute(
            "INSERT INTO moods (user_id, score, note, created_at) VALUES (?, ?, ?, ?)",
            (user_id, score, note, today)
        )
    conn.commit()
    conn.close()


def get_mood_history(user_id: str, days: int = 7) -> list[dict]:
    """ดึงประวัติอารมณ์ย้อนหลัง"""
    conn = get_db()
    since = (datetime.now(BKK).date() - timedelta(days=days)).isoformat()
    rows = conn.execute(
        "SELECT score, note, created_at FROM moods WHERE user_id = ? AND created_at >= ? ORDER BY created_at",
        (user_id, since)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ==================== Routines ====================

def create_routine(user_id: str, title: str, time: str = "", points: int = 5) -> int:
    """สร้างกิจวัตรใหม่"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO routines (user_id, title, time, points) VALUES (?, ?, ?, ?)",
        (user_id, title, time, points)
    )
    routine_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return routine_id


def get_routines(user_id: str) -> list[dict]:
    """ดึงกิจวัตรที่ active"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM routines WHERE user_id = ? AND active = 1 ORDER BY time, id",
        (user_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def is_routine_done_today(routine_id: int, today: str) -> bool:
    """เช็คว่ากิจวัตรนี้ทำแล้ววันนี้หรือยัง"""
    conn = get_db()
    row = conn.execute(
        "SELECT id FROM routine_logs WHERE routine_id = ? AND completed_date = ?",
        (routine_id, today)
    ).fetchone()
    conn.close()
    return row is not None


def complete_routine(routine_id: int, today: str) -> int:
    """เช็คกิจวัตรว่าทำแล้ว → return points earned"""
    conn = get_db()
    routine = conn.execute("SELECT points FROM routines WHERE id = ?", (routine_id,)).fetchone()
    if not routine:
        conn.close()
        return 0

    points = routine["points"]
    try:
        conn.execute(
            "INSERT INTO routine_logs (routine_id, completed_date, points_earned) VALUES (?, ?, ?)",
            (routine_id, today, points)
        )
        conn.commit()
    except sqlite3.IntegrityError:
        pass  # already done today
    conn.close()
    return points


def delete_routine(routine_id: int):
    """ลบกิจวัตร (soft delete)"""
    conn = get_db()
    conn.execute("UPDATE routines SET active = 0 WHERE id = ?", (routine_id,))
    conn.commit()
    conn.close()


# ==================== Stats ====================

def get_user_stats(user_id: str) -> dict:
    """คำนวณ streak และ total points"""
    conn = get_db()

    # Total points
    row = conn.execute(
        "SELECT COALESCE(SUM(rl.points_earned), 0) as total FROM routine_logs rl "
        "JOIN routines r ON rl.routine_id = r.id WHERE r.user_id = ?",
        (user_id,)
    ).fetchone()
    total_points = row["total"] if row else 0

    # Streak: นับวันต่อเนื่องที่ทำกิจวัตรอย่างน้อย 1 อย่าง
    streak = 0
    check_date = datetime.now(BKK).date()
    while True:
        date_str = check_date.isoformat()
        row = conn.execute(
            "SELECT COUNT(*) as cnt FROM routine_logs rl "
            "JOIN routines r ON rl.routine_id = r.id "
            "WHERE r.user_id = ? AND rl.completed_date = ?",
            (user_id, date_str)
        ).fetchone()
        if row and row["cnt"] > 0:
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break

    conn.close()
    return {"streak": streak, "total_points": total_points}


# ==================== Alerts ====================

def save_alert(
    alert_type: str,
    severity: str,
    title: str,
    description: str,
    source: str = "",
    external_id: str = "",
    magnitude: float = 0.0,
    location: str = "",
    url: str = "",
    expires_hours: int = 24,
) -> bool:
    """บันทึก alert ใหม่ — return True ถ้า insert สำเร็จ, False ถ้าซ้ำ"""
    conn = get_db()
    expires_at = (datetime.now(BKK) + timedelta(hours=expires_hours)).isoformat()
    try:
        cursor = conn.execute(
            """INSERT OR IGNORE INTO alerts
               (alert_type, severity, title, description, source,
                external_id, magnitude, location, url, expires_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (alert_type, severity, title, description, source,
             external_id, magnitude, location, url, expires_at),
        )
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()


def get_active_alerts(severity: str | None = None, limit: int = 20) -> list[dict]:
    """ดึง alerts ที่ยังไม่หมดอายุ เรียงจากใหม่สุด"""
    conn = get_db()
    now = datetime.now(BKK).isoformat()
    if severity:
        rows = conn.execute(
            """SELECT * FROM alerts
               WHERE is_active = 1
                 AND (expires_at IS NULL OR expires_at > ?)
                 AND severity = ?
               ORDER BY fetched_at DESC LIMIT ?""",
            (now, severity, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            """SELECT * FROM alerts
               WHERE is_active = 1
                 AND (expires_at IS NULL OR expires_at > ?)
               ORDER BY fetched_at DESC LIMIT ?""",
            (now, limit),
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_latest_critical_alerts(hours_back: int = 6) -> list[dict]:
    """ดึงเฉพาะ critical alerts ใน X ชั่วโมงที่ผ่านมา — ใช้ใน chat context"""
    conn = get_db()
    since = (datetime.now(BKK) - timedelta(hours=hours_back)).isoformat()
    now = datetime.now(BKK).isoformat()
    rows = conn.execute(
        """SELECT * FROM alerts
           WHERE severity = 'critical'
             AND is_active = 1
             AND fetched_at >= ?
             AND (expires_at IS NULL OR expires_at > ?)
           ORDER BY fetched_at DESC LIMIT 3""",
        (since, now),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def expire_old_alerts():
    """Mark expired alerts เป็น is_active=0"""
    conn = get_db()
    now = datetime.now(BKK).isoformat()
    conn.execute(
        "UPDATE alerts SET is_active = 0 WHERE expires_at < ? AND is_active = 1",
        (now,),
    )
    conn.commit()
    conn.close()
