"""
news_fetcher.py — ดึงข้อมูลแผ่นดินไหวและข่าวไทยแบบ real-time
ใช้ USGS Earthquake API (JSON) + BBC Thai RSS (XML)
ไม่ต้องการ API Key — ฟรี 100%
"""

import asyncio
import hashlib
import logging
import xml.etree.ElementTree as ET

import httpx

import database as db

logger = logging.getLogger(__name__)

# ==================== Constants ====================

USGS_URL = (
    "https://earthquake.usgs.gov/fdsnws/event/1/query"
    "?format=geojson&minmagnitude=5.0&limit=10&orderby=time"
)

# Thailand + region: radius 2000km from center of Thailand
USGS_NEAR_THAILAND_URL = (
    "https://earthquake.usgs.gov/fdsnws/event/1/query"
    "?format=geojson&minmagnitude=4.0&limit=10&orderby=time"
    "&latitude=13.0&longitude=101.0&maxradiuskm=2000"
)

RSS_FEEDS = [
    {
        "name": "BBC Thai",
        "url": "https://feeds.bbci.co.uk/thai/rss.xml",
        "source": "bbc_thai",
    },
]

SEVERITY_KEYWORDS = {
    "critical": [
        "แผ่นดินไหว", "สึนามิ", "tsunami", "earthquake",
        "ระเบิด", "ไฟไหม้ใหญ่", "น้ำท่วมหนัก", "สงคราม",
    ],
    "warning": [
        "พายุ", "น้ำท่วม", "ดินถล่ม", "เตือนภัย",
        "อุทกภัย", "วาตภัย", "ฝนหนัก", "ภัยแล้ง",
    ],
}

REQUEST_TIMEOUT = 15.0


# ==================== Earthquake Fetcher ====================

def _classify_earthquake_severity(magnitude: float, is_near_thailand: bool) -> str:
    if magnitude >= 7.0:
        return "critical"
    if magnitude >= 6.0 or (is_near_thailand and magnitude >= 5.0):
        return "warning"
    return "info"


async def fetch_earthquakes() -> int:
    """ดึงข้อมูลแผ่นดินไหวจาก USGS — return จำนวน alerts ใหม่"""
    new_count = 0

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        tasks = [
            client.get(USGS_URL),
            client.get(USGS_NEAR_THAILAND_URL),
        ]
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    seen_ids = set()

    for idx, response in enumerate(responses):
        is_near_thailand = (idx == 1)

        if isinstance(response, Exception):
            logger.warning(f"USGS fetch {idx} failed: {response}")
            continue
        if response.status_code != 200:
            logger.warning(f"USGS HTTP {response.status_code}")
            continue

        try:
            data = response.json()
        except Exception as e:
            logger.error(f"USGS JSON parse error: {e}")
            continue

        for feature in data.get("features", []):
            props = feature.get("properties", {})
            geom = feature.get("geometry", {})
            event_id = feature.get("id", "")

            if not event_id or event_id in seen_ids:
                continue
            seen_ids.add(event_id)

            mag = props.get("mag") or 0.0
            place = props.get("place") or "Unknown"
            coords = geom.get("coordinates", [0, 0, 0])
            depth_km = coords[2] if len(coords) > 2 else 0.0
            url = props.get("url") or ""

            severity = _classify_earthquake_severity(mag, is_near_thailand)
            title = f"แผ่นดินไหว M{mag:.1f} - {place}"
            description = (
                f"แผ่นดินไหวขนาด {mag:.1f} ริกเตอร์ "
                f"บริเวณ {place} ความลึก {depth_km:.0f} กม."
            )

            saved = db.save_alert(
                alert_type="earthquake",
                severity=severity,
                title=title,
                description=description,
                source="usgs",
                external_id=event_id,
                magnitude=mag,
                location=place,
                url=url,
                expires_hours=24,
            )
            if saved:
                new_count += 1
                logger.info(f"New earthquake: {title} [{severity}]")

    return new_count


# ==================== RSS News Fetcher ====================

def _classify_news_severity(title: str, summary: str) -> str:
    text = (title + " " + summary).lower()
    for keyword in SEVERITY_KEYWORDS["critical"]:
        if keyword in text:
            return "critical"
    for keyword in SEVERITY_KEYWORDS["warning"]:
        if keyword in text:
            return "warning"
    return "info"


def _parse_rss_xml(xml_text: str) -> list[dict]:
    """แยก RSS XML -> list of items (ใช้ stdlib)"""
    items = []
    try:
        root = ET.fromstring(xml_text)
        channel = root.find("channel")
        if channel is None:
            return items

        for item in channel.findall("item"):
            title = (item.findtext("title") or "").strip()
            link = (item.findtext("link") or "").strip()
            description = (item.findtext("description") or "").strip()
            guid = (item.findtext("guid") or link).strip()

            if not title or not guid:
                continue

            items.append({
                "title": title,
                "link": link,
                "description": description,
                "guid": guid,
            })
    except ET.ParseError as e:
        logger.error(f"RSS XML parse error: {e}")
    return items


async def fetch_thai_news() -> int:
    """ดึงข่าวจาก RSS feeds — return จำนวน alerts ใหม่"""
    new_count = 0

    async with httpx.AsyncClient(
        timeout=REQUEST_TIMEOUT,
        headers={"User-Agent": "FaAIFriend/1.0"},
        follow_redirects=True,
    ) as client:
        for feed in RSS_FEEDS:
            try:
                response = await client.get(feed["url"])
                if response.status_code != 200:
                    logger.warning(f"RSS {feed['name']} HTTP {response.status_code}")
                    continue

                items = _parse_rss_xml(response.text)
                for item in items[:15]:
                    severity = _classify_news_severity(
                        item["title"], item["description"]
                    )

                    # เก็บแค่ critical + warning
                    if severity == "info":
                        continue

                    external_id = hashlib.md5(
                        item["guid"].encode()
                    ).hexdigest()[:16]

                    saved = db.save_alert(
                        alert_type="news",
                        severity=severity,
                        title=item["title"],
                        description=item["description"][:500],
                        source=feed["source"],
                        external_id=f"{feed['source']}_{external_id}",
                        url=item["link"],
                        expires_hours=12,
                    )
                    if saved:
                        new_count += 1
                        logger.info(f"New news: {item['title'][:60]} [{severity}]")

            except Exception as e:
                logger.error(f"RSS fetch error ({feed['name']}): {e}")

    return new_count


# ==================== Combined Job ====================

async def run_alert_fetch_job():
    """Main job — APScheduler เรียกทุก 7 นาที"""
    logger.info("[AlertJob] Starting fetch cycle...")
    try:
        eq_count, news_count = await asyncio.gather(
            fetch_earthquakes(),
            fetch_thai_news(),
        )
        db.expire_old_alerts()
        logger.info(f"[AlertJob] Done: +{eq_count} earthquakes, +{news_count} news")
    except Exception as e:
        logger.error(f"[AlertJob] Error: {e}")
