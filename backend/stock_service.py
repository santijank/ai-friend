"""
stock_service.py — Stock Price Monitor & Alert System + Smart Analysis
ดึงราคาหุ้นไทย (SET) + ต่างประเทศ (US) ผ่าน yfinance
วิเคราะห์ Technical Indicators (SMA, RSI, Volume) เพื่อให้ AI แนะนำอัจฉริยะ
แจ้งเตือนเมื่อถึงเงื่อนไขที่ผู้ใช้ตั้งไว้
"""

import logging
import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import yfinance as yf
import httpx
import pandas as pd

import database as db
import push_sender

logger = logging.getLogger(__name__)

BKK_TZ = ZoneInfo("Asia/Bangkok")

# หุ้นไทยที่พบบ่อย — ใช้ตรวจจับว่าเป็นหุ้น SET
THAI_STOCK_HINTS = {
    "PTT", "ADVANC", "KBANK", "SCB", "BBL", "KTB", "AOT", "CPALL", "SCC",
    "DELTA", "GULF", "TRUE", "DTAC", "BTS", "MINT", "CPN", "BDMS", "BH",
    "INTUCH", "EA", "GPSC", "BANPU", "IVL", "PTTGC", "PTTEP", "TOP",
    "IRPC", "BEM", "SAWAD", "MTC", "TISCO", "KKP", "TMB", "TTB",
    "CENTEL", "ERW", "HMPRO", "BJC", "MAKRO", "GLOBAL", "CRC",
    "OR", "BGRIM", "RATCH", "EGCO", "WHA", "AMATA", "LH", "AP", "SPALI",
    "ORI", "SC", "SIRI", "PSH", "NOBLE", "QH", "ANAN", "PRUKSA",
    "STEC", "CK", "UNIQ", "MAJOR", "VGI", "PLANB", "RS", "GRAMMY",
    "COM7", "JAS", "THCOM", "DIF", "BTSGIF", "JASIF", "CPNREIT",
}


def format_symbol(user_input: str) -> tuple[str, str]:
    """
    แปลง input ของ user เป็น Yahoo Finance symbol
    Returns: (yahoo_symbol, display_name)
    เช่น "PTT" → ("PTT.BK", "PTT"), "AAPL" → ("AAPL", "AAPL")
    """
    symbol = user_input.strip().upper().replace(" ", "")

    # ถ้ามี .BK อยู่แล้ว
    if symbol.endswith(".BK"):
        display = symbol.replace(".BK", "")
        return symbol, display

    # ตรวจว่าเป็นหุ้นไทยหรือไม่
    if symbol in THAI_STOCK_HINTS:
        return f"{symbol}.BK", symbol

    # default: ใช้ตรง (หุ้นต่างประเทศ)
    return symbol, symbol


# ==================== Yahoo Finance Direct HTTP (bypass yfinance) ====================
# yfinance ถูก block บน cloud servers (Render, Heroku, AWS)
# ใช้ direct HTTP ไปที่ Yahoo Finance v8 chart API แทน — endpoint นี้มักไม่ถูก block

def _safe_float(val, decimals=2):
    """Convert to rounded float, return None if NaN/None"""
    if val is None:
        return None
    try:
        f = float(val)
        if pd.isna(f):
            return None
        return round(f, decimals)
    except (TypeError, ValueError):
        return None


def _yahoo_direct_fetch(symbol: str, range_str: str = '6mo', interval: str = '1d') -> dict | None:
    """
    ดึงข้อมูลหุ้นจาก Yahoo Finance v8 chart API โดยตรง (ไม่ผ่าน yfinance)
    ใช้ได้บน cloud servers ที่ yfinance ถูก block
    Returns raw chart result dict or None
    """
    urls = [
        f'https://query1.finance.yahoo.com/v8/finance/chart/{symbol}',
        f'https://query2.finance.yahoo.com/v8/finance/chart/{symbol}',
    ]

    params = {
        'range': range_str,
        'interval': interval,
        'includePrePost': 'false',
    }

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://finance.yahoo.com/',
        'Origin': 'https://finance.yahoo.com',
    }

    for url in urls:
        try:
            with httpx.Client(headers=headers, timeout=15.0, follow_redirects=True) as client:
                resp = client.get(url, params=params)

                if resp.status_code == 200:
                    data = resp.json()
                    results = data.get('chart', {}).get('result')
                    if results and len(results) > 0:
                        logger.debug(f"Yahoo direct OK: {symbol}")
                        return results[0]

                logger.debug(f"Yahoo direct: HTTP {resp.status_code} for {symbol}")
        except Exception as e:
            logger.debug(f"Yahoo direct error: {symbol}: {e}")

    return None


def get_stock_price_direct(symbol: str) -> dict | None:
    """ดึงราคาหุ้นผ่าน Direct HTTP API (ไม่ใช้ yfinance)"""
    chart = _yahoo_direct_fetch(symbol, range_str='5d', interval='1d')
    if not chart:
        return None

    meta = chart.get('meta', {})
    price = meta.get('regularMarketPrice', 0)
    prev_close = meta.get('chartPreviousClose') or meta.get('previousClose', 0)

    if not price or price <= 0:
        return None

    change = price - prev_close if prev_close else 0
    change_pct = (change / prev_close * 100) if prev_close else 0

    currency = meta.get('currency', '')
    if not currency:
        currency = 'THB' if symbol.endswith('.BK') else 'USD'

    return {
        "symbol": symbol,
        "name": meta.get('shortName') or meta.get('longName') or symbol,
        "price": round(price, 2),
        "previous_close": round(prev_close, 2),
        "change": round(change, 2),
        "change_pct": round(change_pct, 2),
        "currency": currency,
        "market_state": meta.get('marketState', 'UNKNOWN'),
    }


def get_stock_analysis_direct(symbol: str) -> dict | None:
    """วิเคราะห์หุ้นเชิงลึกผ่าน Direct HTTP API (ไม่ใช้ yfinance)"""
    chart = _yahoo_direct_fetch(symbol, range_str='6mo', interval='1d')
    if not chart:
        return None

    meta = chart.get('meta', {})
    indicators = chart.get('indicators', {})
    quotes = indicators.get('quote', [{}])[0]

    closes_raw = quotes.get('close', [])
    highs_raw = quotes.get('high', [])
    lows_raw = quotes.get('low', [])
    volumes_raw = quotes.get('volume', [])

    # Convert to pandas Series (drop None/NaN)
    closes = pd.Series(closes_raw).dropna().reset_index(drop=True)
    highs = pd.Series(highs_raw).dropna().reset_index(drop=True)
    lows = pd.Series(lows_raw).dropna().reset_index(drop=True)
    volumes = pd.Series(volumes_raw).fillna(0).reset_index(drop=True)

    if len(closes) < 20:
        logger.warning(f"Not enough data for direct analysis: {symbol} ({len(closes)} points)")
        return None

    current = float(closes.iloc[-1])
    prev_close = float(closes.iloc[-2]) if len(closes) >= 2 else current

    # --- Moving Averages ---
    sma_20 = _safe_float(closes.rolling(20).mean().iloc[-1]) if len(closes) >= 20 else None
    sma_50 = _safe_float(closes.rolling(50).mean().iloc[-1]) if len(closes) >= 50 else None
    sma_200 = _safe_float(closes.rolling(200).mean().iloc[-1]) if len(closes) >= 200 else None

    # --- RSI (14-day) ---
    rsi = _calculate_rsi(closes, period=14)

    # --- Volume Analysis ---
    avg_vol_20 = _safe_float(volumes.rolling(20).mean().iloc[-1], 0) if len(volumes) >= 20 else None
    current_vol = float(volumes.iloc[-1]) if len(volumes) > 0 else 0
    vol_ratio = _safe_float(current_vol / avg_vol_20) if avg_vol_20 and avg_vol_20 > 0 else None

    # --- Price Performance ---
    perf_1w = _calc_performance(closes, 5)
    perf_1m = _calc_performance(closes, 22)
    perf_3m = _calc_performance(closes, 66)

    # --- Support & Resistance ---
    support = _safe_float(lows.tail(30).min()) if len(lows) > 0 else None
    resistance = _safe_float(highs.tail(30).max()) if len(highs) > 0 else None

    # --- 52-week High/Low ---
    high_52w = _safe_float(highs.max())
    low_52w = _safe_float(lows.min())

    # --- Trend Detection ---
    trend = "sideways"
    if sma_20 and sma_50:
        if current > sma_20 > sma_50:
            trend = "uptrend"
        elif current < sma_20 < sma_50:
            trend = "downtrend"

    # --- Signal Summary ---
    signals = []
    if rsi is not None:
        if rsi > 70:
            signals.append("RSI > 70 (Overbought — อาจปรับตัวลง)")
        elif rsi < 30:
            signals.append("RSI < 30 (Oversold — อาจเด้งกลับ)")
    if sma_20 and sma_50 and len(closes) >= 51:
        sma20_series = closes.rolling(20).mean()
        sma50_series = closes.rolling(50).mean()
        sma20_prev = _safe_float(sma20_series.iloc[-2])
        sma50_prev = _safe_float(sma50_series.iloc[-2])
        if sma20_prev and sma50_prev:
            if sma_20 > sma_50 and sma20_prev <= sma50_prev:
                signals.append("Golden Cross (SMA20 ตัด SMA50 ขึ้น — สัญญาณบวก)")
            elif sma_20 < sma_50 and sma20_prev >= sma50_prev:
                signals.append("Death Cross (SMA20 ตัด SMA50 ลง — สัญญาณลบ)")
    if vol_ratio and vol_ratio > 2.0:
        signals.append(f"Volume สูงผิดปกติ ({vol_ratio:.1f}x เฉลี่ย)")
    if support and current <= support * 1.02:
        signals.append(f"ใกล้แนวรับ {support}")
    if resistance and current >= resistance * 0.98:
        signals.append(f"ใกล้แนวต้าน {resistance}")

    currency = meta.get('currency', '')
    if not currency:
        currency = 'THB' if symbol.endswith('.BK') else 'USD'

    return {
        "symbol": symbol,
        "name": meta.get('shortName') or meta.get('longName') or symbol,
        "currency": currency,
        "sector": "",
        "industry": "",
        "price": round(current, 2),
        "prev_close": round(prev_close, 2),
        "change_pct": round((current - prev_close) / prev_close * 100, 2) if prev_close else 0,
        "market_cap": None,
        "pe_ratio": None,
        "div_yield": None,
        "sma_20": sma_20,
        "sma_50": sma_50,
        "sma_200": sma_200,
        "rsi_14": _safe_float(rsi, 1),
        "volume": int(current_vol) if current_vol else None,
        "avg_volume_20d": int(avg_vol_20) if avg_vol_20 else None,
        "volume_ratio": vol_ratio,
        "support_30d": support,
        "resistance_30d": resistance,
        "high_52w": high_52w,
        "low_52w": low_52w,
        "perf_1w": perf_1w,
        "perf_1m": perf_1m,
        "perf_3m": perf_3m,
        "trend": trend,
        "signals": signals,
    }


def get_stock_price(symbol: str) -> dict | None:
    """
    ดึงราคาหุ้นปัจจุบัน — ลอง Direct HTTP ก่อน, fallback yfinance
    Returns: {symbol, name, price, change, change_pct, currency, market_state}
    """
    # Layer 1: Direct HTTP (works on cloud servers like Render)
    direct = get_stock_price_direct(symbol)
    if direct:
        return direct

    # Layer 2: yfinance (fallback for local development)
    try:
        ticker = yf.Ticker(symbol)
        info = ticker.fast_info

        price = info.get("lastPrice") or info.get("last_price", 0)
        prev_close = info.get("previousClose") or info.get("previous_close", 0)

        if not price or price <= 0:
            logger.warning(f"No price data for {symbol}")
            return None

        change = price - prev_close if prev_close else 0
        change_pct = (change / prev_close * 100) if prev_close else 0

        # ดึงชื่อเต็ม
        try:
            full_info = ticker.info
            name = full_info.get("shortName") or full_info.get("longName") or symbol
            currency = full_info.get("currency", "THB" if symbol.endswith(".BK") else "USD")
            market_state = full_info.get("marketState", "UNKNOWN")
        except Exception:
            name = symbol
            currency = "THB" if symbol.endswith(".BK") else "USD"
            market_state = "UNKNOWN"

        return {
            "symbol": symbol,
            "name": name,
            "price": round(price, 2),
            "previous_close": round(prev_close, 2),
            "change": round(change, 2),
            "change_pct": round(change_pct, 2),
            "currency": currency,
            "market_state": market_state,
        }

    except Exception as e:
        logger.error(f"Failed to get price for {symbol}: {e}")
        return None


def get_stock_analysis(symbol: str) -> dict | None:
    """
    วิเคราะห์หุ้นเชิงลึก — ลอง Direct HTTP ก่อน, fallback yfinance
    SMA, RSI, Volume Profile, แนวรับ/แนวต้าน
    """
    # Layer 1: Direct HTTP (works on cloud servers)
    direct = get_stock_analysis_direct(symbol)
    if direct:
        return direct

    # Layer 2: yfinance (fallback for local development)
    try:
        ticker = yf.Ticker(symbol)

        # ดึงข้อมูลราคาย้อนหลัง 6 เดือน
        hist = ticker.history(period="6mo")
        if hist.empty or len(hist) < 20:
            logger.warning(f"Not enough history for {symbol}")
            return None

        closes = hist["Close"]
        volumes = hist["Volume"]
        highs = hist["High"]
        lows = hist["Low"]
        current = closes.iloc[-1]
        prev_close = closes.iloc[-2] if len(closes) >= 2 else current

        # --- Moving Averages ---
        sma_20 = closes.rolling(20).mean().iloc[-1] if len(closes) >= 20 else None
        sma_50 = closes.rolling(50).mean().iloc[-1] if len(closes) >= 50 else None
        sma_200 = closes.rolling(200).mean().iloc[-1] if len(closes) >= 200 else None

        # --- RSI (14-day) ---
        rsi = _calculate_rsi(closes, period=14)

        # --- Volume Analysis ---
        avg_vol_20 = volumes.rolling(20).mean().iloc[-1] if len(volumes) >= 20 else None
        current_vol = volumes.iloc[-1]
        vol_ratio = (current_vol / avg_vol_20) if avg_vol_20 and avg_vol_20 > 0 else None

        # --- Price Performance ---
        perf_1w = _calc_performance(closes, 5)
        perf_1m = _calc_performance(closes, 22)
        perf_3m = _calc_performance(closes, 66)

        # --- Support & Resistance (simple method: recent lows/highs) ---
        recent_30 = hist.tail(30)
        support = round(recent_30["Low"].min(), 2) if len(recent_30) > 0 else None
        resistance = round(recent_30["High"].max(), 2) if len(recent_30) > 0 else None

        # --- 52-week High/Low ---
        high_52w = round(highs.max(), 2) if len(hist) > 0 else None
        low_52w = round(lows.min(), 2) if len(hist) > 0 else None

        # --- Trend Detection ---
        trend = "sideways"
        if sma_20 and sma_50:
            if current > sma_20 > sma_50:
                trend = "uptrend"
            elif current < sma_20 < sma_50:
                trend = "downtrend"

        # --- Signal Summary ---
        signals = []
        if rsi is not None:
            if rsi > 70:
                signals.append("RSI > 70 (Overbought — อาจปรับตัวลง)")
            elif rsi < 30:
                signals.append("RSI < 30 (Oversold — อาจเด้งกลับ)")
        if sma_20 and sma_50:
            if sma_20 > sma_50 and closes.rolling(20).mean().iloc[-2] <= closes.rolling(50).mean().iloc[-2]:
                signals.append("Golden Cross (SMA20 ตัด SMA50 ขึ้น — สัญญาณบวก)")
            elif sma_20 < sma_50 and closes.rolling(20).mean().iloc[-2] >= closes.rolling(50).mean().iloc[-2]:
                signals.append("Death Cross (SMA20 ตัด SMA50 ลง — สัญญาณลบ)")
        if vol_ratio and vol_ratio > 2.0:
            signals.append(f"Volume สูงผิดปกติ ({vol_ratio:.1f}x เฉลี่ย)")
        if support and current and current <= support * 1.02:
            signals.append(f"ใกล้แนวรับ {support}")
        if resistance and current and current >= resistance * 0.98:
            signals.append(f"ใกล้แนวต้าน {resistance}")

        # --- Company Info ---
        try:
            info = ticker.info
            name = info.get("shortName") or info.get("longName") or symbol
            currency = info.get("currency", "THB" if symbol.endswith(".BK") else "USD")
            sector = info.get("sector", "")
            industry = info.get("industry", "")
            market_cap = info.get("marketCap", 0)
            pe_ratio = info.get("trailingPE") or info.get("forwardPE")
            div_yield = info.get("dividendYield")
        except Exception:
            name = symbol
            currency = "THB" if symbol.endswith(".BK") else "USD"
            sector = industry = ""
            market_cap = pe_ratio = div_yield = None

        return {
            "symbol": symbol,
            "name": name,
            "currency": currency,
            "sector": sector,
            "industry": industry,
            "price": round(current, 2),
            "prev_close": round(prev_close, 2),
            "change_pct": round((current - prev_close) / prev_close * 100, 2) if prev_close else 0,
            "market_cap": market_cap,
            "pe_ratio": round(pe_ratio, 2) if pe_ratio else None,
            "div_yield": round(div_yield * 100, 2) if div_yield else None,
            "sma_20": round(sma_20, 2) if sma_20 else None,
            "sma_50": round(sma_50, 2) if sma_50 else None,
            "sma_200": round(sma_200, 2) if sma_200 else None,
            "rsi_14": round(rsi, 1) if rsi else None,
            "volume": int(current_vol) if current_vol else None,
            "avg_volume_20d": int(avg_vol_20) if avg_vol_20 else None,
            "volume_ratio": round(vol_ratio, 2) if vol_ratio else None,
            "support_30d": support,
            "resistance_30d": resistance,
            "high_52w": high_52w,
            "low_52w": low_52w,
            "perf_1w": perf_1w,
            "perf_1m": perf_1m,
            "perf_3m": perf_3m,
            "trend": trend,
            "signals": signals,
        }

    except Exception as e:
        logger.error(f"Stock analysis failed for {symbol}: {e}")
        return None


def _calculate_rsi(prices, period=14) -> float | None:
    """คำนวณ RSI (Relative Strength Index)"""
    if len(prices) < period + 1:
        return None
    deltas = prices.diff()
    gains = deltas.where(deltas > 0, 0.0)
    losses = (-deltas).where(deltas < 0, 0.0)
    avg_gain = gains.rolling(period).mean().iloc[-1]
    avg_loss = losses.rolling(period).mean().iloc[-1]
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return round(100 - (100 / (1 + rs)), 1)


def _calc_performance(closes, days: int) -> float | None:
    """คำนวณ % performance ย้อนหลัง N วัน"""
    if len(closes) <= days:
        return None
    old = closes.iloc[-days - 1]
    current = closes.iloc[-1]
    if old and old > 0:
        return round((current - old) / old * 100, 2)
    return None


def format_analysis_for_ai(analysis: dict) -> str:
    """แปลง analysis dict เป็นข้อความสั้นที่ AI อ่านง่าย (ประหยัด token)"""
    if not analysis:
        return ""

    lines = [f"📊 ข้อมูลหุ้น {analysis['name']} ({analysis['symbol']})"]

    # Price
    lines.append(f"ราคา: {analysis['price']} {analysis['currency']} ({analysis['change_pct']:+.2f}%)")

    # Fundamentals
    parts = []
    if analysis.get("sector"):
        parts.append(f"กลุ่ม: {analysis['sector']}")
    if analysis.get("pe_ratio"):
        parts.append(f"P/E: {analysis['pe_ratio']}")
    if analysis.get("div_yield"):
        parts.append(f"Div Yield: {analysis['div_yield']}%")
    if analysis.get("market_cap"):
        mc = analysis["market_cap"]
        if mc > 1e12:
            parts.append(f"Market Cap: {mc/1e12:.1f}T")
        elif mc > 1e9:
            parts.append(f"Market Cap: {mc/1e9:.1f}B")
        elif mc > 1e6:
            parts.append(f"Market Cap: {mc/1e6:.0f}M")
    if parts:
        lines.append(" | ".join(parts))

    # Technicals
    tech = []
    if analysis.get("sma_20"):
        tech.append(f"SMA20: {analysis['sma_20']}")
    if analysis.get("sma_50"):
        tech.append(f"SMA50: {analysis['sma_50']}")
    if analysis.get("rsi_14"):
        tech.append(f"RSI: {analysis['rsi_14']}")
    if tech:
        lines.append("Technical: " + " | ".join(tech))

    # Support/Resistance
    if analysis.get("support_30d") and analysis.get("resistance_30d"):
        lines.append(f"แนวรับ: {analysis['support_30d']} | แนวต้าน: {analysis['resistance_30d']}")

    # Performance
    perfs = []
    if analysis.get("perf_1w") is not None:
        perfs.append(f"1W: {analysis['perf_1w']:+.1f}%")
    if analysis.get("perf_1m") is not None:
        perfs.append(f"1M: {analysis['perf_1m']:+.1f}%")
    if analysis.get("perf_3m") is not None:
        perfs.append(f"3M: {analysis['perf_3m']:+.1f}%")
    if perfs:
        lines.append("ผลตอบแทน: " + " | ".join(perfs))

    # Volume
    if analysis.get("volume_ratio"):
        lines.append(f"Volume: {analysis['volume_ratio']:.1f}x เฉลี่ย 20 วัน")

    # Trend
    trend_th = {"uptrend": "ขาขึ้น", "downtrend": "ขาลง", "sideways": "ไซด์เวย์"}
    lines.append(f"แนวโน้ม: {trend_th.get(analysis['trend'], analysis['trend'])}")

    # Signals
    if analysis.get("signals"):
        lines.append("สัญญาณ: " + " / ".join(analysis["signals"]))

    return "\n".join(lines)


def detect_stock_symbols_in_message(message: str) -> list[str]:
    """ตรวจจับชื่อหุ้นในข้อความแชท — ใช้ตอน detect ว่าผู้ใช้ถามเรื่องหุ้น"""
    symbols = []

    # ตรวจจับหุ้นไทยที่รู้จัก
    msg_upper = message.upper()
    for sym in THAI_STOCK_HINTS:
        if sym in msg_upper:
            # ตรวจว่าเป็น whole word
            pattern = r'\b' + re.escape(sym) + r'\b'
            if re.search(pattern, msg_upper):
                symbols.append(sym)

    # ตรวจจับหุ้นต่างประเทศ (1-5 ตัวอักษร uppercase, ไม่ใช่คำธรรมดา)
    common_words = {"THE", "AND", "FOR", "NOT", "BUT", "ALL", "CAN", "HAD",
                    "HER", "WAS", "ONE", "OUR", "OUT", "ARE", "HAS", "HIS",
                    "HOW", "ITS", "MAY", "NEW", "NOW", "OLD", "SEE", "WAY",
                    "WHO", "DID", "GET", "LET", "SAY", "SHE", "TOO", "USE",
                    "NONE", "SET", "BIG", "TOP", "LOW", "HIGH", "BEST",
                    "GOOD", "LONG", "DAY", "TELL"}
    us_pattern = re.findall(r'\b([A-Z]{2,5})\b', message)
    for sym in us_pattern:
        if sym not in common_words and sym not in THAI_STOCK_HINTS and sym not in symbols:
            symbols.append(sym)

    return symbols[:3]  # max 3 symbols per message


def get_market_overview() -> dict | None:
    """
    ดึงสถานะตลาดรวม — SET Index, S&P 500, ทองคำ, น้ำมัน
    ใช้ get_stock_price() ซึ่งลอง Direct HTTP ก่อน yfinance
    """
    indices = {
        "^SET.BK": "SET Index",
        "^GSPC": "S&P 500",
        "^DJI": "Dow Jones",
        "GC=F": "Gold",
        "CL=F": "Crude Oil",
    }
    results = {}
    for sym, name in indices.items():
        try:
            data = get_stock_price(sym)
            if data:
                results[name] = {
                    "price": data["price"],
                    "change_pct": data["change_pct"],
                }
        except Exception as e:
            logger.debug(f"Market overview skip {sym}: {e}")
    return results if results else None


def format_market_overview_for_ai(overview: dict) -> str:
    """แปลง market overview เป็นข้อความสั้น"""
    if not overview:
        return ""
    lines = ["🌐 ภาพรวมตลาด:"]
    for name, data in overview.items():
        emoji = "🟢" if data["change_pct"] >= 0 else "🔴"
        lines.append(f"{emoji} {name}: {data['price']:,.2f} ({data['change_pct']:+.2f}%)")
    return "\n".join(lines)


def get_watchlist_summary(user_id: str) -> str:
    """
    สรุป watchlist ของผู้ใช้ พร้อมราคาปัจจุบัน
    ใช้ inject เข้า AI context ตอนคุยเรื่องหุ้น
    """
    alerts = db.get_user_stock_alerts(user_id)
    if not alerts:
        return ""

    # Group unique symbols
    symbols = {}
    for a in alerts:
        sym = a["symbol"]
        if sym not in symbols:
            symbols[sym] = {
                "display": a["display_name"],
                "alerts": [],
            }
        alert_desc = ""
        if a["alert_type"] == "price_above":
            alert_desc = f"เตือนถ้าขึ้นเกิน {a['target_value']}"
        elif a["alert_type"] == "price_below":
            alert_desc = f"เตือนถ้าตกต่ำกว่า {a['target_value']}"
        elif a["alert_type"] == "change_pct":
            alert_desc = f"เตือนถ้าเปลี่ยน ±{a['target_value']}%"
        symbols[sym]["alerts"].append(alert_desc)

    # Fetch current prices
    lines = [f"📋 หุ้นที่ {user_id[:8]} ติดตามอยู่:"]
    for sym, info in symbols.items():
        price_data = get_stock_price(sym)
        if price_data:
            emoji = "📈" if price_data["change_pct"] >= 0 else "📉"
            lines.append(
                f"{emoji} {info['display']}: {price_data['price']} {price_data['currency']} "
                f"({price_data['change_pct']:+.2f}%) — {', '.join(info['alerts'])}"
            )
        else:
            lines.append(f"• {info['display']}: ดึงราคาไม่ได้")

    return "\n".join(lines)


def get_watchlist_brief(user_id: str) -> str | None:
    """
    สรุปสั้น ๆ สำหรับ morning brief — หุ้นที่ติดตามเปลี่ยนแปลงอย่างไร
    """
    alerts = db.get_user_stock_alerts(user_id)
    if not alerts:
        return None

    symbols = set(a["symbol"] for a in alerts)
    display_map = {a["symbol"]: a["display_name"] for a in alerts}

    parts = []
    for sym in symbols:
        price_data = get_stock_price(sym)
        if price_data:
            display = display_map.get(sym, sym)
            pct = price_data["change_pct"]
            emoji = "📈" if pct >= 0 else "📉"
            parts.append(f"{emoji}{display} {pct:+.1f}%")

    if not parts:
        return None
    return "หุ้นวันนี้: " + " | ".join(parts)


# ==================== Cached Versions (อ่านจาก DB ก่อน, fallback ดึงสด) ====================

def get_stock_price_cached(symbol: str) -> dict | None:
    """ดึงราคาหุ้นจาก cache ก่อน — ถ้าหมดอายุค่อย fetch ใหม่"""
    cached = db.get_stock_cache(symbol, max_age_minutes=10)
    if cached and cached.get("price"):
        return {
            "symbol": cached["symbol"],
            "name": cached.get("name", symbol),
            "price": cached["price"],
            "previous_close": cached.get("previous_close", 0),
            "change": round(cached["price"] - (cached.get("previous_close") or 0), 2),
            "change_pct": cached.get("change_pct", 0),
            "currency": cached.get("currency", "THB" if symbol.endswith(".BK") else "USD"),
            "market_state": cached.get("market_state", "CACHED"),
        }
    # Cache miss → ดึงสดแต่ limit timeout
    try:
        data = get_stock_price(symbol)
        if data:
            db.upsert_stock_cache(data)
        return data
    except Exception as e:
        logger.warning(f"get_stock_price_cached fallback failed for {symbol}: {e}")
        return None


def get_stock_analysis_cached(symbol: str) -> dict | None:
    """ดึง analysis จาก cache ก่อน — ถ้าหมดอายุค่อย fetch ใหม่"""
    cached = db.get_stock_cache(symbol, max_age_minutes=10)
    if cached and cached.get("price"):
        # สร้าง analysis dict จาก cache
        return {
            "symbol": cached["symbol"],
            "name": cached.get("name", symbol),
            "currency": cached.get("currency", "THB" if symbol.endswith(".BK") else "USD"),
            "sector": cached.get("sector", ""),
            "industry": cached.get("industry", ""),
            "price": cached["price"],
            "prev_close": cached.get("previous_close", 0),
            "change_pct": cached.get("change_pct", 0),
            "market_cap": cached.get("market_cap"),
            "pe_ratio": cached.get("pe_ratio"),
            "div_yield": cached.get("div_yield"),
            "sma_20": cached.get("sma_20"),
            "sma_50": cached.get("sma_50"),
            "sma_200": cached.get("sma_200"),
            "rsi_14": cached.get("rsi_14"),
            "volume": cached.get("volume"),
            "avg_volume_20d": cached.get("avg_volume_20d"),
            "volume_ratio": cached.get("volume_ratio"),
            "support_30d": cached.get("support_30d"),
            "resistance_30d": cached.get("resistance_30d"),
            "high_52w": cached.get("high_52w"),
            "low_52w": cached.get("low_52w"),
            "perf_1w": cached.get("perf_1w"),
            "perf_1m": cached.get("perf_1m"),
            "perf_3m": cached.get("perf_3m"),
            "trend": cached.get("trend", "sideways"),
            "signals": cached.get("signals", []),
        }
    # Cache miss → ดึงสด
    try:
        data = get_stock_analysis(symbol)
        if data:
            db.upsert_stock_cache(data)
        return data
    except Exception as e:
        logger.warning(f"get_stock_analysis_cached fallback failed for {symbol}: {e}")
        return None


def get_market_overview_cached() -> dict | None:
    """ดึง market overview จาก cache ก่อน"""
    cached = db.get_market_cache(max_age_minutes=10)
    if cached:
        return cached
    # Cache miss → ดึงสด + cache
    try:
        data = get_market_overview()
        if data:
            for name, info in data.items():
                # หา symbol จาก name
                sym_map = {
                    "SET Index": "^SET.BK", "S&P 500": "^GSPC",
                    "Dow Jones": "^DJI", "Gold": "GC=F", "Crude Oil": "CL=F",
                }
                sym = sym_map.get(name, "")
                db.upsert_market_cache(name, sym, info["price"], info["change_pct"])
        return data
    except Exception as e:
        logger.warning(f"get_market_overview_cached fallback failed: {e}")
        return None


def get_watchlist_summary_cached(user_id: str) -> str:
    """สรุป watchlist จาก cache — ไม่เรียก yfinance"""
    alerts = db.get_user_stock_alerts(user_id)
    if not alerts:
        return ""

    symbols = {}
    for a in alerts:
        sym = a["symbol"]
        if sym not in symbols:
            symbols[sym] = {"display": a["display_name"], "alerts": []}
        alert_desc = ""
        if a["alert_type"] == "price_above":
            alert_desc = f"เตือนถ้าขึ้นเกิน {a['target_value']}"
        elif a["alert_type"] == "price_below":
            alert_desc = f"เตือนถ้าตกต่ำกว่า {a['target_value']}"
        elif a["alert_type"] == "change_pct":
            alert_desc = f"เตือนถ้าเปลี่ยน ±{a['target_value']}%"
        symbols[sym]["alerts"].append(alert_desc)

    lines = [f"📋 หุ้นที่ติดตามอยู่:"]
    for sym, info in symbols.items():
        cached = db.get_stock_cache(sym, max_age_minutes=15)
        if cached and cached.get("price"):
            emoji = "📈" if (cached.get("change_pct") or 0) >= 0 else "📉"
            currency = cached.get("currency", "THB")
            lines.append(
                f"{emoji} {info['display']}: {cached['price']} {currency} "
                f"({cached.get('change_pct', 0):+.2f}%) — {', '.join(info['alerts'])}"
            )
        else:
            lines.append(f"• {info['display']}: รอข้อมูล")

    return "\n".join(lines)


def get_watchlist_brief_cached(user_id: str) -> str | None:
    """สรุปสั้น ๆ สำหรับ morning brief — จาก cache"""
    alerts = db.get_user_stock_alerts(user_id)
    if not alerts:
        return None

    symbols = set(a["symbol"] for a in alerts)
    display_map = {a["symbol"]: a["display_name"] for a in alerts}

    parts = []
    for sym in symbols:
        cached = db.get_stock_cache(sym, max_age_minutes=15)
        if cached and cached.get("price"):
            display = display_map.get(sym, sym)
            pct = cached.get("change_pct", 0)
            emoji = "📈" if pct >= 0 else "📉"
            parts.append(f"{emoji}{display} {pct:+.1f}%")

    if not parts:
        return None
    return "หุ้นวันนี้: " + " | ".join(parts)


# ==================== Background Pre-fetch Job ====================

def refresh_stock_cache():
    """
    Background job — ดึงข้อมูลหุ้นทั้งหมดใน watchlist + market overview
    แล้วบันทึกลง cache ทุก 5 นาที (เรียกจาก APScheduler)
    """
    logger.info("🔄 Stock cache refresh started...")

    # 1. ดึง symbols ทั้งหมดจาก watchlist
    alerts = db.get_all_active_stock_alerts()
    symbols = list(set(a["symbol"] for a in alerts))
    logger.info(f"  Symbols to cache: {symbols}")

    cached_count = 0
    for symbol in symbols:
        try:
            # ดึง full analysis (รวม price, technical, fundamental)
            analysis = get_stock_analysis(symbol)
            if analysis:
                db.upsert_stock_cache(analysis)
                cached_count += 1
                logger.debug(f"  ✅ Cached {symbol}: {analysis.get('price')}")
            else:
                # fallback: ดึงแค่ราคา
                price_data = get_stock_price(symbol)
                if price_data:
                    db.upsert_stock_cache(price_data)
                    cached_count += 1
                    logger.debug(f"  ✅ Cached {symbol} (price only)")
        except Exception as e:
            logger.warning(f"  ❌ Failed to cache {symbol}: {e}")

    # 2. ดึง market overview
    market_count = 0
    try:
        market = get_market_overview()
        if market:
            sym_map = {
                "SET Index": "^SET.BK", "S&P 500": "^GSPC",
                "Dow Jones": "^DJI", "Gold": "GC=F", "Crude Oil": "CL=F",
            }
            for name, info in market.items():
                sym = sym_map.get(name, "")
                db.upsert_market_cache(name, sym, info["price"], info["change_pct"])
                market_count += 1
    except Exception as e:
        logger.warning(f"  ❌ Market overview cache failed: {e}")

    logger.info(f"🔄 Stock cache refresh done: {cached_count}/{len(symbols)} stocks, {market_count} indices")


def is_stock_related_message(message: str) -> bool:
    """ตรวจว่าข้อความเกี่ยวกับหุ้น/การลงทุนหรือไม่"""
    stock_keywords = [
        "หุ้น", "ราคาหุ้น", "ลงทุน", "กองทุน", "ตลาดหุ้น", "SET", "พอร์ต",
        "ซื้อหุ้น", "ขายหุ้น", "วิเคราะห์หุ้น", "แนะนำหุ้น", "กราฟ",
        "แนวรับ", "แนวต้าน", "เทคนิคอล", "RSI", "SMA", "ถัวเฉลี่ย",
        "P/E", "ปันผล", "dividend", "stock", "invest",
        "NASDAQ", "S&P", "ดาวโจนส์", "Dow Jones",
    ]
    msg_lower = message.lower()
    if any(kw.lower() in msg_lower for kw in stock_keywords):
        return True
    # ถ้ามีชื่อหุ้นที่รู้จัก
    return len(detect_stock_symbols_in_message(message)) > 0


def check_stock_alerts():
    """
    เช็คเงื่อนไข stock alerts ทั้งหมด — เรียกจาก scheduler ทุก 5 นาที
    ถ้าถึงเป้า → ส่ง push notification
    """
    alerts = db.get_all_active_stock_alerts()
    if not alerts:
        return

    # Group by symbol เพื่อลด API calls
    symbols = set(a["symbol"] for a in alerts)
    prices = {}

    for symbol in symbols:
        data = get_stock_price(symbol)
        if data:
            prices[symbol] = data

    now = datetime.now(BKK_TZ)

    for alert in alerts:
        symbol = alert["symbol"]
        if symbol not in prices:
            continue

        price_data = prices[symbol]
        current_price = price_data["price"]
        change_pct = price_data["change_pct"]
        alert_type = alert["alert_type"]
        target = alert["target_value"]

        # อัพเดทราคาล่าสุด
        db.update_stock_price(alert["id"], current_price)

        # เช็คว่าเพิ่งแจ้งไปหรือยัง (ไม่แจ้งซ้ำภายใน 30 นาที)
        last_notified = alert.get("last_notified_at")
        if last_notified:
            try:
                last_dt = datetime.fromisoformat(last_notified).replace(tzinfo=BKK_TZ)
                if now - last_dt < timedelta(minutes=30):
                    continue
            except Exception:
                pass

        triggered = False
        emoji = ""
        message = ""

        if alert_type == "price_above" and current_price >= target:
            triggered = True
            emoji = "📈"
            currency = price_data["currency"]
            message = f"{alert['display_name']} ขึ้นถึง {current_price} {currency}! (เป้า {target})"

        elif alert_type == "price_below" and current_price <= target:
            triggered = True
            emoji = "📉"
            currency = price_data["currency"]
            message = f"{alert['display_name']} ตกถึง {current_price} {currency}! (เป้า {target})"

        elif alert_type == "change_pct" and abs(change_pct) >= target:
            triggered = True
            if change_pct > 0:
                emoji = "📈"
                message = f"{alert['display_name']} ขึ้น {change_pct:+.2f}% (ราคา {current_price})"
            else:
                emoji = "📉"
                message = f"{alert['display_name']} ลง {change_pct:+.2f}% (ราคา {current_price})"

        if triggered:
            title = f"{emoji} แจ้งเตือนหุ้น {alert['display_name']}"
            logger.info(f"Stock alert triggered: {title} — {message}")

            # ส่ง push notification
            push_sender.send_push_to_user(
                alert["user_id"], title, message,
                notification_type="stock_alert"
            )

            # บันทึกว่าแจ้งแล้ว
            db.mark_stock_notified(alert["id"])
