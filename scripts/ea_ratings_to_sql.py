import json
import re
import time
import requests
from bs4 import BeautifulSoup

URLS = [
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/liverpool/9",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/fc-barcelona/241",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/real-madrid/243",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/man-utd/11",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/manchester-city/10",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/arsenal/1",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/spurs/18",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/juventus/45",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/milano-fc/131681",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/lombardia-fc/131682",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/ssc-napoli/48",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/fc-bayern-munchen/21",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/leverkusen/32",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/borussia-dortmund/22",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/atletico-de-madrid/240",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/paris-sg/73",
    "https://www.ea.com/es/games/ea-sports-fc/ratings/teams-ratings/chelsea/5"
]

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
}

SESSION = requests.Session()
SESSION.headers.update(HEADERS)

# ── Helpers ────────────────────────────────────────────────────────────────────

def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def _round500k(v: int) -> int:
    return round(v / 500_000) * 500_000


def _calc_price_clause(ovr: int) -> tuple[int, int]:
    """Return (price, clause) in euros based on OVR rating."""
    import random
    if ovr >= 91:
        price  = 120_000_000 + (ovr - 91) * 20_000_000 + random.randint(0, 15_000_000)
        clause = 200_000_000 + (ovr - 91) * 25_000_000 + random.randint(0, 20_000_000)
    elif ovr >= 88:
        price  = 70_000_000 + (ovr - 88) * 15_000_000 + random.randint(0, 10_000_000)
        clause = 120_000_000 + (ovr - 88) * 15_000_000 + random.randint(0, 15_000_000)
    elif ovr >= 85:
        price  = 40_000_000 + (ovr - 85) * 10_000_000 + random.randint(0, 8_000_000)
        clause = 70_000_000 + (ovr - 85) * 12_000_000 + random.randint(0, 10_000_000)
    elif ovr >= 82:
        price  = 20_000_000 + (ovr - 82) * 6_000_000 + random.randint(0, 5_000_000)
        clause = 35_000_000 + (ovr - 82) * 8_000_000 + random.randint(0, 7_000_000)
    elif ovr >= 79:
        price  = 10_000_000 + (ovr - 79) * 3_000_000 + random.randint(0, 3_000_000)
        clause = 18_000_000 + (ovr - 79) * 4_000_000 + random.randint(0, 4_000_000)
    elif ovr >= 76:
        price  = 5_000_000 + (ovr - 76) * 1_500_000 + random.randint(0, 2_000_000)
        clause = 9_000_000 + (ovr - 76) * 2_500_000 + random.randint(0, 3_000_000)
    elif ovr >= 73:
        price  = 2_000_000 + (ovr - 73) * 800_000 + random.randint(0, 1_000_000)
        clause = 4_000_000 + (ovr - 73) * 1_200_000 + random.randint(0, 1_500_000)
    else:
        price  = 500_000 + max(ovr - 65, 0) * 150_000 + random.randint(0, 500_000)
        clause = 1_500_000 + max(ovr - 65, 0) * 250_000 + random.randint(0, 800_000)

    price  = _round500k(price)
    clause = _round500k(clause)
    if clause < price * 1.4:
        clause = _round500k(int(price * 1.5))
    return price, clause

def walk(obj):
    """Recorre recursivamente dicts/listas y yield (key, value)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k, v
            yield from walk(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk(item)

# ── Fetch ──────────────────────────────────────────────────────────────────────

def fetch_html(url: str) -> str:
    resp = SESSION.get(url, timeout=30)
    resp.raise_for_status()
    return resp.text

# ── Parse ──────────────────────────────────────────────────────────────────────

def parse_next_data(html: str):
    """
    EA Sports FC usa Next.js SSR — los datos del equipo y jugadores
    vienen serializados en el tag <script id="__NEXT_DATA__">.
    """
    soup = BeautifulSoup(html, "html.parser")

    tag = soup.find("script", id="__NEXT_DATA__")
    if not tag or not tag.string:
        raise ValueError("No se encontró __NEXT_DATA__ en la página.")

    return json.loads(tag.string)

def clean_team_name(raw: str) -> str:
    """Quita prefijos/sufijos de EA del nombre del equipo."""
    name = re.sub(r"^EA\s+SPORTS\s+FC[™\u2122]?\s*\d*\s*", "", raw, flags=re.IGNORECASE)
    name = re.sub(r"\s+Player\s+Ratings?\s*$", "", name, flags=re.IGNORECASE)
    return name.strip() or raw.strip()

def find_team_name(data: dict, soup: BeautifulSoup) -> str:
    """Nombre del equipo: del h1 o del JSON, limpiando el texto de EA."""
    h1 = soup.find("h1")
    if h1:
        return clean_team_name(h1.get_text(strip=True))
    for k, v in walk(data):
        if isinstance(v, str) and k.lower() in ("teamname", "team_name", "clubname"):
            return clean_team_name(v)
    raise ValueError("No se pudo detectar el nombre del equipo.")

CREST_KEY_HINTS = (
    "crest", "logo", "badge", "teamimage", "clubimage",
    "teamlogo", "clublogo", "emblem", "shield",
)
PLAYER_URL_EXCLUSIONS = (
    "player", "headshot", "avatar", "person", "face",
)
EA_CDN = "drop-assets.ea.com"

def find_crest(data: dict, soup: BeautifulSoup | None = None, team_name: str | None = None) -> str | None:
    # 1) HTML — img con alt igual al nombre del equipo en el CDN de EA
    #    Estructura detectada: <img alt="Liverpool" class="Picture_image__..." src="https://drop-assets.ea.com/...">
    if soup and team_name:
        for img in soup.find_all("img"):
            src = img.get("src") or img.get("data-src") or ""
            alt = (img.get("alt") or "").strip()
            if EA_CDN in src and alt.lower() == team_name.lower():
                return src

    # 2) HTML — cualquier <img> del CDN de EA que no sea de jugador
    if soup:
        for img in soup.find_all("img"):
            src = img.get("src") or img.get("data-src") or ""
            css = " ".join(img.get("class") or []).lower()
            if (
                EA_CDN in src
                and not any(ex in src.lower() for ex in PLAYER_URL_EXCLUSIONS)
                and ("picture_image" in css or "team" in css or "crest" in css or "logo" in css)
            ):
                return src

    # 3) JSON — buscar por nombre de key
    for k, v in walk(data):
        if isinstance(v, str) and v.startswith("http") and any(h in k.lower() for h in CREST_KEY_HINTS):
            return v

    # 4) JSON — buscar por CDN de EA en el valor
    for k, v in walk(data):
        if (
            isinstance(v, str)
            and EA_CDN in v
            and not any(ex in v.lower() for ex in PLAYER_URL_EXCLUSIONS)
        ):
            return v

    return None

def extract_str(val) -> str | None:
    """Extrae string de un valor que puede ser str o dict (como los de EA)."""
    if val is None:
        return None
    if isinstance(val, str):
        return val.strip() or None
    if isinstance(val, dict):
        # EA anida objetos: {"shortLabel": "MD", "label": "Medio derecho", ...}
        for key in ("shortLabel", "label", "name", "id"):
            v = val.get(key)
            if v and isinstance(v, str):
                return v.strip()
    return None

def build_full_name(p: dict) -> str | None:
    """
    EA guarda el nombre completo en 'longName' o lo divide en
    'firstName' + 'lastName'. Prioriza el nombre completo.
    """
    # Nombre completo directo
    long = extract_str(p.get("longName") or p.get("fullName") or p.get("playerFullName"))
    if long and " " in long:
        return long

    # Combinar firstName + lastName
    first = extract_str(p.get("firstName") or p.get("first_name"))
    last  = extract_str(p.get("lastName") or p.get("last_name") or p.get("surname"))
    if first and last:
        return f"{first} {last}"

    # Si solo hay longName (aunque no tenga espacio) o name como fallback
    if long:
        return long
    short = extract_str(p.get("name") or p.get("playerName") or p.get("commonName"))
    return short

def find_players(data: dict) -> list[dict]:
    """
    Busca dentro del JSON arrays de jugadores que tengan name + rating/ovr.
    EA usa distintas keys y puede anidar position/nationality como objetos.
    """
    best: list[dict] = []

    for k, v in walk(data):
        if not (isinstance(v, list) and len(v) > 3 and isinstance(v[0], dict)):
            continue

        sample = v[0]
        sample_keys = set(sample.keys())

        HAS_NAME = bool({"name", "playerName", "longName", "firstName", "commonName"} & sample_keys)
        HAS_OVR  = bool({"overall", "ovr", "rating", "overallRating", "baseRating"} & sample_keys)

        if not (HAS_NAME and HAS_OVR):
            continue

        parsed = []
        for p in v:
            name = build_full_name(p)
            ovr_raw = (
                p.get("overall") or p.get("ovr") or
                p.get("rating") or p.get("overallRating") or
                p.get("baseRating")
            )
            if not name or not ovr_raw:
                continue
            try:
                ovr = int(ovr_raw)
            except (ValueError, TypeError):
                continue

            # position puede ser string o dict {"shortLabel": "MD", ...}
            pos_raw = (
                p.get("position") or p.get("pos") or
                p.get("preferredPosition") or p.get("positionFull")
            )
            pos = extract_str(pos_raw)

            # nationality puede ser string o dict {"label": "España", ...}
            country_raw = (
                p.get("nationality") or p.get("nation") or
                p.get("country") or p.get("countryName")
            )
            country = extract_str(country_raw)

            headshot = (
                p.get("headshotUrl") or p.get("headshot") or
                p.get("playerImageUrl") or p.get("avatarUrl")
            )
            if isinstance(headshot, dict):
                headshot = extract_str(headshot)

            parsed.append({
                "name": name,
                "ovr": ovr,
                "position": pos,
                "country_name": country,
                "headshot_url": headshot if isinstance(headshot, str) else None,
                "card_image_url": None,
            })

        if len(parsed) > len(best):
            best = parsed

    # Deduplicate
    seen: set = set()
    uniq = []
    for p in best:
        key = (p["name"], p["ovr"], p["position"], p["country_name"])
        if key not in seen:
            seen.add(key)
            uniq.append(p)

    return uniq

# ── SQL builder ────────────────────────────────────────────────────────────────

def build_sql(teams_data: list[dict]) -> str:
    out = ["-- Mercatto seed generated from EA Ratings", "begin;"]

    # ── Teams ──
    out.append("\n-- Teams")
    for t in teams_data:
        name = sql_escape(t["team_name"])
        crest = t["crest_url"]
        if crest:
            out.append(
                f"insert into teams (name, crest_url) values ('{name}', '{sql_escape(crest)}') "
                f"on conflict (name) do update set crest_url = excluded.crest_url;"
            )
        else:
            out.append(
                f"insert into teams (name) values ('{name}') on conflict (name) do nothing;"
            )

    # ── Players ──
    out.append("\n-- Players")
    for t in teams_data:
        for p in t["players"]:
            name    = sql_escape(p["name"])
            ovr     = p["ovr"]
            pos     = f"'{sql_escape(p['position'])}'" if p["position"] else "null"
            country = f"'{sql_escape(p['country_name'])}'" if p["country_name"] else "null"
            headshot = f"'{sql_escape(p['headshot_url'])}'" if p.get("headshot_url") else "null"
            card     = f"'{sql_escape(p['card_image_url'])}'" if p.get("card_image_url") else "null"
            price, clause = _calc_price_clause(ovr)

            out.append(
                "insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) "
                f"values ('{name}', {ovr}, {pos}, {country}, {headshot}, {card}, {price}, {clause}) "
                "on conflict (name, ovr, position) do update set "
                "headshot_url = coalesce(excluded.headshot_url, players.headshot_url), "
                "card_image_url = coalesce(excluded.card_image_url, players.card_image_url), "
                "country_name = coalesce(excluded.country_name, players.country_name), "
                "price = excluded.price, clause = excluded.clause;"
            )

    # ── Team rosters ──
    out.append("\n-- Team rosters (team_players)")
    for t in teams_data:
        team = sql_escape(t["team_name"])
        for p in t["players"]:
            name    = sql_escape(p["name"])
            ovr     = p["ovr"]
            pos     = p["position"]
            country = p["country_name"]

            where = [f"p.name = '{name}'", f"p.ovr = {ovr}"]
            where.append(f"p.position = '{sql_escape(pos)}'" if pos else "p.position is null")
            where.append(f"p.country_name = '{sql_escape(country)}'" if country else "p.country_name is null")

            out.append(
                "insert into team_players (team_id, player_id)\n"
                f"select t.id, p.id from teams t join players p on {' and '.join(where)}\n"
                f"where t.name = '{team}'\n"
                "on conflict (team_id, player_id) do nothing;"
            )

    out.append("commit;")
    return "\n".join(out)

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    teams_data = []

    for url in URLS:
        try:
            html = fetch_html(url)
            soup = BeautifulSoup(html, "html.parser")
            data = parse_next_data(html)
            team_name = find_team_name(data, soup)
            crest_url = find_crest(data, soup, team_name)
            players   = find_players(data)

            crest_log = f"  crest={crest_url[:60]}…" if crest_url else "  crest=NOT FOUND"
            print(f"[OK] {team_name}: {len(players)} jugadores{crest_log}")
            teams_data.append({
                "url": url,
                "team_name": team_name,
                "crest_url": crest_url,
                "players": players,
            })

        except Exception as e:
            print(f"[ERROR] {url}\n       {e}")

        time.sleep(0.8)  # pequeña pausa entre requests

    if not teams_data:
        print("No se pudo procesar ningún equipo.")
        return

    sql = build_sql(teams_data)
    with open("mercatto_seed.sql", "w", encoding="utf-8") as f:
        f.write(sql)

    total_players = sum(len(t["players"]) for t in teams_data)
    print(f"\nGenerado: mercatto_seed.sql  ({len(teams_data)} equipos, {total_players} jugadores)")

if __name__ == "__main__":
    main()
