"""
push_sender.py — Firebase Cloud Messaging Push Notification Sender
ส่ง push notification ไปยังอุปกรณ์ของผู้ใช้ผ่าน FCM
"""

import json
import os
import logging

import firebase_admin
from firebase_admin import credentials, messaging

import database as db

logger = logging.getLogger(__name__)

_initialized = False


def init_firebase():
    """เริ่มต้น Firebase Admin SDK — เรียกตอน server start"""
    global _initialized
    if _initialized:
        return

    # วิธี 1: FIREBASE_SERVICE_ACCOUNT_JSON (JSON string ใน env var)
    sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    if sa_json:
        try:
            sa_dict = json.loads(sa_json)
            cred = credentials.Certificate(sa_dict)
            firebase_admin.initialize_app(cred)
            _initialized = True
            logger.info("[OK] Firebase Admin initialized from env var")
            return
        except Exception as e:
            logger.error(f"Firebase init from env var failed: {e}")

    # วิธี 2: GOOGLE_APPLICATION_CREDENTIALS (path to file)
    sa_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if sa_path and os.path.exists(sa_path):
        try:
            cred = credentials.Certificate(sa_path)
            firebase_admin.initialize_app(cred)
            _initialized = True
            logger.info(f"[OK] Firebase Admin initialized from file: {sa_path}")
            return
        except Exception as e:
            logger.error(f"Firebase init from file failed: {e}")

    # วิธี 3: service-account.json ใน project root
    local_path = "service-account.json"
    if os.path.exists(local_path):
        try:
            cred = credentials.Certificate(local_path)
            firebase_admin.initialize_app(cred)
            _initialized = True
            logger.info("[OK] Firebase Admin initialized from service-account.json")
            return
        except Exception as e:
            logger.error(f"Firebase init from local file failed: {e}")

    logger.warning("[WARN] Firebase Admin NOT initialized — no credentials found. Push notifications disabled.")


def send_push_to_user(user_id: str, title: str, body: str) -> int:
    """
    ส่ง push notification ไปยังอุปกรณ์ทั้งหมดของผู้ใช้
    Returns: จำนวนอุปกรณ์ที่ส่งสำเร็จ
    """
    if not _initialized:
        logger.warning("Firebase not initialized — skipping push")
        return 0

    tokens = db.get_user_fcm_tokens(user_id)
    if not tokens:
        logger.info(f"No FCM tokens for user {user_id}")
        return 0

    success_count = 0
    for token in tokens:
        try:
            # ใช้ data-only message เพื่อให้ background handler ทำงาน
            # (notification message จะถูก Android OS intercept → ไม่ trigger handler)
            message = messaging.Message(
                data={
                    "type": "reminder",
                    "title": title,
                    "body": body,
                },
                android=messaging.AndroidConfig(priority="high"),
                token=token,
            )
            messaging.send(message)
            success_count += 1
            logger.info(f"Push sent to {token[:20]}...")
        except messaging.UnregisteredError:
            logger.warning(f"Token expired, removing: {token[:20]}...")
            db.delete_fcm_token(token)
        except Exception as e:
            logger.error(f"Push failed for {token[:20]}...: {e}")

    return success_count
