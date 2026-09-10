"""Refresh a factual index of publicly available, completed official games.

The published index contains metadata, checksums and official URLs, not recent
game moves or broadcast commentary. Apps download a selected KIF for local use.
No login, paywall, photograph, editorial text or live/incomplete game is copied.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urljoin, urlparse

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ("oui", "ouza", "kiou", "kisei", "eiou", "ryuou")
TAGS = ("先手", "後手", "開始日時", "終了日時", "棋戦", "戦型", "場所", "持ち時間", "手合割")
TERMINALS = ("投了", "詰み", "千日手", "持将棋", "切れ負け")
MAX_BYTES = 2 * 1024 * 1024


def official_url(url: str, extension: str = "") -> bool:
    parsed = urlparse(url)
    return (parsed.scheme in ("http", "https") and parsed.netloc == "live.shogi.or.jp"
            and not parsed.query and not parsed.fragment and ".." not in parsed.path
            and re.fullmatch(r"/[a-z]+/(?:[A-Za-z0-9_./-]*)", parsed.path) is not None
            and (not extension or parsed.path.endswith(extension)))


def fetch(url: str) -> bytes:
    if not official_url(url):
        raise ValueError("Untrusted official URL")
    request = urllib.request.Request(url, headers={"User-Agent": "ShogiStudio-Catalog/0.20 (+https://github.com/DipperHide/shogi-studio)"})
    with urllib.request.urlopen(request, timeout=20) as response:
        if not official_url(response.url):
            raise ValueError("Unexpected redirect")
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("Source exceeds size limit")
    return data


def decode(raw: bytes) -> str:
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("cp932")


def discover(html: str, url: str, minimum_year: int) -> list[str]:
    links = set()
    for href in re.findall(r'''href\s*=\s*["']([^"']+)["']''', html, re.I):
        page = urljoin(url, href.replace("&amp;", "&"))
        if not official_url(page, ".html") or "/kifu/" not in page:
            continue
        date = re.search(r"(20\d{6})\d*\.html$", page)
        if date and int(date[1][:4]) >= minimum_year:
            links.add(page)
    return sorted(links, reverse=True)


def normalize_kif(raw: bytes) -> dict:
    tags, moves = {}, []
    for line in decode(raw).replace("\r", "").split("\n"):
        line = line.strip()
        if not line or line.startswith(("*", "#")):
            continue
        if "：" in line:
            key, value = line.split("：", 1)
            if key in TAGS:
                tags[key] = value.strip()
        match = re.match(r"^(\d+)\s+(.+)", line)
        if match:
            # Keep only the move token, so commentary and time edits do not
            # invalidate a previously downloaded, identical game.
            number = int(match[1])
            if number != len(moves) + 1:
                raise ValueError("Nonsequential move number")
            token = re.split(r"\s+\(", match[2])[0].replace(" ", "").replace("　", "")
            moves.append(f"{number} {token}")
    if not moves or not any(word in moves[-1] for word in TERMINALS):
        raise ValueError("Game has not finished")
    if len(moves) < 2 or len(moves) > 1001 or not all(tags.get(key) for key in ("先手", "後手", "開始日時", "棋戦")):
        raise ValueError("Incomplete game metadata")
    facts = "\n".join(f"{key}：{tags[key]}" for key in TAGS if key in tags)
    kif = facts + "\n手数----指手---------消費時間--\n" + "\n".join(moves)
    return {"tags": tags, "plies": len(moves) - 1, "terminal": moves[-1], "kif": kif,
            "moves_sha256": hashlib.sha256("\n".join(moves).encode()).hexdigest()}


def record(page: str) -> dict:
    html = decode(fetch(page))
    match = re.search(r'''KIF_FILE_NAME\s*=\s*["']([^"']+)''', html)
    if not match:
        raise ValueError("No public KIF link")
    url = urljoin(page, match[1])
    if not official_url(url, ".kif"):
        raise ValueError("Untrusted KIF URL")
    raw = fetch(url)
    item = normalize_kif(raw)
    item.pop("kif")  # Recent moves are fetched by the app, never republished here.
    item.update(id=Path(urlparse(url).path).stem, source=page, kif_source=url,
                sha256=hashlib.sha256(raw).hexdigest())
    return item


def update(output: Path, minimum_year: int) -> dict:
    prior = json.loads(output.read_text(encoding="utf-8")) if output.exists() else {"games": []}
    games = {item["id"]: item for item in prior["games"]}
    pages, failures, sources = set(), [], []
    for event in EVENTS:
        # This official service currently serves KIF over HTTP only. The
        # published index is delivered to the app by HTTPS with move hashes.
        url = f"http://live.shogi.or.jp/{event}/"
        try:
            links = discover(decode(fetch(url)), url, minimum_year)
            pages.update(links[:50])
            sources.append({"url": url, "pages": len(links)})
        except Exception as error:
            failures.append({"source": url, "error": str(error)})
    successful = 0
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = {pool.submit(record, page): page for page in pages}
        for job in as_completed(jobs):
            try:
                item = job.result()
                games[item["id"]] = item
                successful += 1
            except Exception as error:
                failures.append({"source": jobs[job], "error": str(error)})
    if not successful:
        raise RuntimeError("No completed public record could be refreshed; keeping the existing index")
    result = {"schema": 1, "updated_utc": datetime.now(timezone.utc).isoformat(),
              "sources": sources, "games": sorted(games.values(), key=lambda g: (g["tags"]["開始日時"], g["id"]), reverse=True)}
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(".tmp")
    temp.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(output)
    return {"games": len(games), "refreshed": successful, "latest": result["games"][0]["tags"]["開始日時"], "skipped": failures}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "godot/assets/data/tournament-index.json")
    parser.add_argument("--minimum-year", type=int, default=datetime.now(timezone.utc).year - 1)
    args = parser.parse_args()
    print(json.dumps(update(args.output, args.minimum_year), ensure_ascii=False, indent=2))
