"""
Mercatto seed builder — datos + imágenes desde sofifa, hosteadas en Supabase.

Flujo:
    1. Scrapea sofifa para cada equipo (nombre, escudo, plantilla activa).
    2. Descarga headshot de cada jugador y crest del equipo desde el CDN de
       sofifa (`cdn.sofifa.net`) usando `Referer: https://sofifa.com/` para
       saltar la protección hotlink.
    3. Sube cada imagen al bucket público de Supabase Storage `fc-assets`
       (rutas: `players/sofifa_<id>.png`, `teams/sofifa_<id>.png`).
       El bucket se crea si no existe.
    4. Genera `mercatto_seed.sql` con `INSERT ... ON CONFLICT` para teams,
       players y team_players, apuntando a las URLs públicas de Supabase.

Variables de entorno requeridas (prod):
    SUPABASE_URL                  ej. https://abcdefgh.supabase.co
    SUPABASE_SERVICE_ROLE_KEY     service-role key del proyecto

Uso:
    set SUPABASE_URL=https://xxx.supabase.co
    set SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
    python scripts/sofifa_to_sql.py

    # Sin subir, solo descarga local + SQL con paths locales:
    python scripts/sofifa_to_sql.py --no-upload

    # Solo un equipo:
    python scripts/sofifa_to_sql.py --only 243
"""

import argparse
import json
import mimetypes
import os
import random
import sys
import time
import urllib.error
import urllib.request
from html import unescape
from pathlib import Path
from typing import Optional

from bs4 import BeautifulSoup


# ── Equipos ──────────────────────────────────────────────────────────────────

# IDs de sofifa (coinciden con los IDs de EA Sports FC).
TEAMS_SOFIFA: list[int] = [
    9,        # Liverpool
    241,      # FC Barcelona
    243,      # Real Madrid
    11,       # Manchester United
    10,       # Manchester City
    1,        # Arsenal
    18,       # Tottenham
    45,       # Juventus
    131681,   # Inter
    131682,   # Milan
    48,       # Napoli
    21,       # Bayern München
    32,       # Bayer Leverkusen
    22,       # Borussia Dortmund
    240,      # Atlético Madrid
    73,       # Paris Saint-Germain
    5,        # Chelsea
]


# ── Constantes ───────────────────────────────────────────────────────────────

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)

HTML_HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
    "Accept-Encoding": "identity",
    "Connection": "keep-alive",
}

# Cloudflare/sofifa exigen Referer para servir las imágenes.
IMG_HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    "Referer": "https://sofifa.com/",
    "Accept-Encoding": "identity",
}

CDN_PLAYER_TPL = "https://cdn.sofifa.net/players/{prefix}/{suffix}/26_180.png"
CDN_TEAM_TPL   = "https://cdn.sofifa.net/meta/team/{team_id}/180.png"

ASSETS_DIR  = Path(__file__).parent / "_assets"
PLAYERS_DIR = ASSETS_DIR / "players"
TEAMS_DIR   = ASSETS_DIR / "teams"

BUCKET = "fc-assets"

# Sofifa marca como cedido en distintos idiomas.
LOAN_HEADERS = {"on loan", "cedidos", "ausgeliehen", "prêté", "prestiti"}


# ── Helpers SQL / pricing ────────────────────────────────────────────────────

def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def _round500k(v: int) -> int:
    return round(v / 500_000) * 500_000


def _calc_price_clause(ovr: int) -> tuple[int, int]:
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


# ── HTTP helpers ─────────────────────────────────────────────────────────────

def _fetch_with_retry(url: str, headers: dict, timeout: int, retries: int = 3) -> Optional[bytes]:
    """GET con retry para DNS/timeouts transitorios. Re-raise solo HTTPError."""
    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last_err = e
            time.sleep(1.5 * (attempt + 1))
    raise last_err if last_err else RuntimeError(f"Falló {url}")


def fetch_html(url: str) -> str:
    data = _fetch_with_retry(url, HTML_HEADERS, timeout=30)
    return data.decode("utf-8", errors="replace")


def fetch_image(url: str) -> Optional[bytes]:
    """Descarga una imagen del CDN de sofifa. None si HTTP != 200 o red caída."""
    try:
        return _fetch_with_retry(url, IMG_HEADERS, timeout=20)
    except urllib.error.HTTPError as e:
        print(f"      [skip] {url} HTTP {e.code}", file=sys.stderr)
        return None
    except Exception as e:  # noqa: BLE001
        print(f"      [skip] {url} {e}", file=sys.stderr)
        return None


# ── Sofifa parsing ───────────────────────────────────────────────────────────

def _team_meta(soup: BeautifulSoup) -> tuple[str, Optional[str]]:
    name = None
    crest = None
    for tag in soup.find_all("script", type="application/ld+json"):
        if not tag.string:
            continue
        try:
            data = json.loads(tag.string)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict) and data.get("@type") == "Organization":
            name = data.get("name") or name
            crest = data.get("logo") or crest
    if not name:
        h1 = soup.find("h1")
        if h1:
            name = h1.get_text(strip=True)
    return (name or "?"), crest


def _parse_player_row(tr) -> Optional[dict]:
    cells = tr.find_all("td", recursive=False)
    if len(cells) < 6:
        return None

    avatar = cells[0]
    name_cell = cells[1]

    link = name_cell.find("a", attrs={"data-tippy-content": True})
    if not link:
        return None
    full_name = unescape(link["data-tippy-content"]).strip() or link.get_text(strip=True)

    flag = name_cell.find("img", class_="flag")
    country = (flag.get("title") or "").strip() if flag else None

    first_pos = name_cell.find("span", class_="pos")
    position = first_pos.get_text(strip=True) if first_pos else None

    ovr_cell = tr.find("td", attrs={"data-col": "oa"})
    if not ovr_cell:
        return None
    em = ovr_cell.find("em")
    ovr_txt = (em.get("title") or em.get_text(strip=True)) if em else ovr_cell.get_text(strip=True)
    try:
        ovr = int(ovr_txt)
    except (TypeError, ValueError):
        return None

    sofifa_id = None
    check = avatar.find(class_="player-check")
    if check:
        sofifa_id = check.get("id")

    return {
        "name": full_name,
        "ovr": ovr,
        "position": position,
        "country_name": country or None,
        "sofifa_id": sofifa_id,
        "headshot_url": None,    # se rellena después con la URL pública de Supabase
        "card_image_url": None,
    }


def parse_sofifa_team(html: str) -> dict:
    soup = BeautifulSoup(html, "html.parser")
    team_name, crest = _team_meta(soup)

    players: list[dict] = []
    seen: set = set()

    for article in soup.find_all("article"):
        h5 = article.find("h5")
        if not h5:
            continue
        title = h5.get_text(strip=True).lower()
        if title in LOAN_HEADERS:
            continue
        table = article.find("table")
        if not table or not table.thead:
            continue
        thead_text = table.thead.get_text(" ", strip=True).lower()
        if not any(k in thead_text for k in ("name", "nombre", "spieler", "joueur", "giocatore")):
            continue
        for tr in table.find_all("tr"):
            if "persist-header" in (tr.get("class") or []):
                continue
            row = _parse_player_row(tr)
            if not row:
                continue
            key = row["sofifa_id"] or (row["name"], row["ovr"], row["position"])
            if key in seen:
                continue
            seen.add(key)
            players.append(row)

    return {"team_name": team_name, "crest_url": crest, "players": players}


# ── Image cache + Supabase Storage upload ────────────────────────────────────

class SupabaseUploader:
    """Subida directa al endpoint /storage/v1 — sin SDK."""

    def __init__(self, url: str, service_key: str, bucket: str):
        self.base = url.rstrip("/")
        self.key = service_key
        self.bucket = bucket
        self._public_prefix = f"{self.base}/storage/v1/object/public/{bucket}"

    def _request(self, method: str, path: str, body: Optional[bytes] = None,
                 content_type: Optional[str] = None,
                 extra_headers: Optional[dict] = None,
                 retries: int = 3) -> tuple[int, bytes]:
        headers = {
            "Authorization": f"Bearer {self.key}",
            "apikey": self.key,
        }
        if content_type:
            headers["Content-Type"] = content_type
        if extra_headers:
            headers.update(extra_headers)
        last_err = None
        for attempt in range(retries):
            req = urllib.request.Request(
                f"{self.base}{path}", data=body, headers=headers, method=method,
            )
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return r.status, r.read()
            except urllib.error.HTTPError as e:
                return e.code, e.read()
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last_err = e
                time.sleep(1.5 * (attempt + 1))
                continue
        return 0, str(last_err).encode("utf-8")

    def ensure_bucket(self) -> None:
        code, _ = self._request("GET", f"/storage/v1/bucket/{self.bucket}")
        if code == 200:
            print(f"  Bucket '{self.bucket}' ya existe.")
            return
        print(f"  Creando bucket '{self.bucket}' (público)…")
        code, body = self._request(
            "POST", "/storage/v1/bucket",
            body=json.dumps({
                "id": self.bucket,
                "name": self.bucket,
                "public": True,
            }).encode("utf-8"),
            content_type="application/json",
        )
        if code not in (200, 201):
            raise RuntimeError(
                f"No se pudo crear el bucket {self.bucket}: HTTP {code} - "
                f"{body.decode('utf-8', errors='ignore')}"
            )

    def upload(self, remote_path: str, file_bytes: bytes,
               content_type: str) -> Optional[str]:
        """Sube (upsert) y devuelve la URL pública. None si falla."""
        code, body = self._request(
            "POST",
            f"/storage/v1/object/{self.bucket}/{remote_path}",
            body=file_bytes,
            content_type=content_type,
            extra_headers={"x-upsert": "true"},
        )
        if code in (200, 201):
            return f"{self._public_prefix}/{remote_path}"
        # Algunos despliegues devuelven 409 incluso con x-upsert; devolvemos
        # la URL pública porque el objeto ya está allí.
        if code == 409:
            return f"{self._public_prefix}/{remote_path}"
        print(
            f"      [upload-fail] {remote_path} HTTP {code}: "
            f"{body.decode('utf-8', errors='ignore')[:200]}",
            file=sys.stderr,
        )
        return None


def _player_cdn_url(sofifa_id: str) -> Optional[str]:
    """Construye la URL del headshot en cdn.sofifa.net a partir del ID.

    Sofifa parte el ID como `<prefijo>/<sufijo>`, ambos *zero-padded a 3
    dígitos*. Ej: 239053 -> "239/053", 80807 -> "080/807", 192119 -> "192/119".
    """
    try:
        n = int(sofifa_id)
    except (TypeError, ValueError):
        return None
    return CDN_PLAYER_TPL.format(prefix=f"{n // 1000:03d}", suffix=f"{n % 1000:03d}")


def _team_cdn_url(team_id: int) -> str:
    return CDN_TEAM_TPL.format(team_id=team_id)


def _cache_or_download(local_path: Path, url: str) -> Optional[bytes]:
    if local_path.exists():
        return local_path.read_bytes()
    data = fetch_image(url)
    if data is None:
        return None
    local_path.parent.mkdir(parents=True, exist_ok=True)
    local_path.write_bytes(data)
    return data


def localize_player(sofifa_id: str, uploader: Optional[SupabaseUploader]) -> Optional[str]:
    if not sofifa_id:
        return None
    cdn_url = _player_cdn_url(sofifa_id)
    if not cdn_url:
        return None
    local_path = PLAYERS_DIR / f"sofifa_{sofifa_id}.png"
    data = _cache_or_download(local_path, cdn_url)
    if data is None:
        return None
    if uploader is None:
        return f"/players/sofifa_{sofifa_id}.png"
    return uploader.upload(
        f"players/sofifa_{sofifa_id}.png",
        data,
        mimetypes.guess_type(local_path.name)[0] or "image/png",
    )


def localize_team(team_id: int, uploader: Optional[SupabaseUploader]) -> Optional[str]:
    cdn_url = _team_cdn_url(team_id)
    local_path = TEAMS_DIR / f"sofifa_{team_id}.png"
    data = _cache_or_download(local_path, cdn_url)
    if data is None:
        return None
    if uploader is None:
        return f"/teams/sofifa_{team_id}.png"
    return uploader.upload(
        f"teams/sofifa_{team_id}.png",
        data,
        mimetypes.guess_type(local_path.name)[0] or "image/png",
    )


# ── SQL builder (idéntico al estilo del script EA) ───────────────────────────

def build_sql(teams_data: list[dict]) -> str:
    out = ["-- Mercatto seed (sofifa data + Supabase Storage images)", "begin;"]

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

    out.append("\n-- Players")
    for t in teams_data:
        for p in t["players"]:
            name     = sql_escape(p["name"])
            ovr      = p["ovr"]
            pos      = f"'{sql_escape(p['position'])}'" if p["position"] else "null"
            country  = f"'{sql_escape(p['country_name'])}'" if p["country_name"] else "null"
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
            where.append(
                f"p.country_name = '{sql_escape(country)}'" if country else "p.country_name is null"
            )
            out.append(
                "insert into team_players (team_id, player_id) "
                f"select t.id, p.id from teams t join players p on {' and '.join(where)} "
                f"where t.name = '{team}' "
                "on conflict (team_id, player_id) do nothing;"
            )

    out.append("\ncommit;")
    return "\n".join(out)


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", type=int, action="append",
                    help="Procesa solo el/los IDs sofifa dados.")
    ap.add_argument("--out", default="mercatto_seed.sql",
                    help="Ruta del SQL de salida.")
    ap.add_argument("--no-upload", action="store_true",
                    help="No sube a Supabase, solo descarga local + SQL con paths /players/...")
    args = ap.parse_args()

    target_ids = set(args.only) if args.only else None
    teams = [t for t in TEAMS_SOFIFA if (target_ids is None or t in target_ids)]

    uploader: Optional[SupabaseUploader] = None
    if not args.no_upload:
        url = os.environ.get("SUPABASE_URL")
        key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        if not url or not key:
            print(
                "ERROR: faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY.\n"
                "       Define las variables o usa --no-upload.",
                file=sys.stderr,
            )
            return 1
        uploader = SupabaseUploader(url, key, BUCKET)
        print(f"Conectando a Supabase: {url}")
        try:
            uploader.ensure_bucket()
        except Exception as e:  # noqa: BLE001
            print(f"ERROR: {e}", file=sys.stderr)
            return 1
        print()

    teams_data: list[dict] = []
    for sofifa_id in teams:
        sofifa_url = f"https://sofifa.com/team/{sofifa_id}/?hl=es-ES"
        try:
            html = fetch_html(sofifa_url)
            data = parse_sofifa_team(html)
        except Exception as e:  # noqa: BLE001
            print(f"[ERROR] sofifa {sofifa_url}\n        {e}", file=sys.stderr)
            continue

        # Crest del equipo desde el CDN de sofifa.
        new_crest = localize_team(sofifa_id, uploader)
        if new_crest:
            data["crest_url"] = new_crest
        else:
            data["crest_url"] = None

        # Headshots de cada jugador.
        with_img = 0
        for p in data["players"]:
            url = localize_player(p.get("sofifa_id"), uploader)
            if url:
                p["headshot_url"] = url
                with_img += 1

        print(
            f"[OK] {data['team_name']}: {len(data['players'])} jugadores  "
            f"({with_img} con foto)"
        )
        teams_data.append(data)
        time.sleep(0.4)

    if not teams_data:
        print("No se procesó ningún equipo.", file=sys.stderr)
        return 1

    sql = build_sql(teams_data)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(sql)

    total = sum(len(t["players"]) for t in teams_data)
    with_img = sum(1 for t in teams_data for p in t["players"] if p.get("headshot_url"))
    print(
        f"\nGenerado: {args.out}\n"
        f"  Equipos    : {len(teams_data)}\n"
        f"  Jugadores  : {total}\n"
        f"  Con foto   : {with_img}"
    )
    if uploader is None:
        print("  (modo --no-upload: las URLs apuntan a /players y /teams locales)")
    else:
        print(f"  Bucket     : {BUCKET} en {uploader.base}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
