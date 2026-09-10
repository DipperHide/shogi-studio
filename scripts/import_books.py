"""Index the two user-supplied EPUBs in spine order; preserve each page for QA.

This is source ingestion, not a claim that OCR/interactive lesson authoring is done.
No source EPUB is altered. Only explicitly provided files are opened.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from PIL import Image
from io import BytesIO

ROOT = Path(__file__).resolve().parents[1]


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def resolve(base: str, href: str) -> str:
    return posixpath.normpath(posixpath.join(posixpath.dirname(base), href.split("#")[0]))


def ingest(path: Path, book_id: str, title: str) -> dict:
    destination = ROOT / "course_sources" / book_id
    destination.mkdir(parents=True, exist_ok=True)
    with ZipFile(path) as archive:
        container = ET.fromstring(archive.read("META-INF/container.xml"))
        opf_path = next(n.attrib["full-path"] for n in container.iter() if local_name(n.tag) == "rootfile")
        opf = ET.fromstring(archive.read(opf_path))
        manifest = {n.attrib["id"]: n.attrib for n in opf.iter() if local_name(n.tag) == "item"}
        spine = [n.attrib["idref"] for n in opf.iter() if local_name(n.tag) == "itemref"]
        pages = []
        for item_id in spine:
            item = manifest[item_id]
            html_path = resolve(opf_path, item["href"])
            document = ET.fromstring(archive.read(html_path))
            images = []
            for node in document.iter():
                if local_name(node.tag) not in {"img", "image"}:
                    continue
                href = node.attrib.get("src", node.attrib.get("{http://www.w3.org/1999/xlink}href", node.attrib.get("href")))
                if href:
                    images.append(resolve(html_path, href))
            body = next((n for n in document.iter() if local_name(n.tag) == "body"), document)
            page = {"index": len(pages), "spine_id": item_id, "html": html_path, "text": " ".join(body.itertext()).strip(), "images": [], "interactive_status": "unreviewed"}
            for i, image_path in enumerate(images):
                data = archive.read(image_path)
                image = Image.open(BytesIO(data))
                suffix = PurePosixPath(image_path).suffix.lower()
                name = f"page-{len(pages):03d}-{i}{suffix}"
                (destination / name).write_bytes(data)
                page["images"].append({"file": name, "archive_path": image_path, "width": image.width, "height": image.height, "sha256": hashlib.sha256(data).hexdigest()})
            pages.append(page)
        result = {"id": book_id, "title": title, "source_path": str(path), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "page_count": len(pages), "image_count": sum(len(p["images"]) for p in pages), "pages": pages}
        (destination / "index.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        return {k: v for k, v in result.items() if k != "pages"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("intro", type=Path)
    parser.add_argument("opening", type=Path)
    args = parser.parse_args()
    reports = [ingest(args.intro, "hanyu-intro", "羽生善治的将棋入门（修订版）"), ingest(args.opening, "hanyu-opening", "羽生善治的将棋入门：序盘下法（修订版）")]
    target = ROOT / "review" / "app" / "complete"
    target.mkdir(parents=True, exist_ok=True)
    (target / "book-import.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    for report in reports:
        print(f"{report['id']}: {report['page_count']} pages, {report['image_count']} images preserved; interactive authoring remains pending")


if __name__ == "__main__":
    main()
