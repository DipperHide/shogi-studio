"""Recover text and word coordinates from the user-provided scanned books.

Each page is resumable and tied to its source hash. OCR output remains a draft
until the diagram positions and instructional content have been reviewed.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import threading
import time
from PIL import Image
from tesserocr import PyTessBaseAPI, PSM, OEM, RIL

ROOT = Path(__file__).resolve().parents[1]
LOCAL = threading.local()


def recognize(task: tuple[Path, dict]) -> dict:
    folder, page = task
    output = folder / f"page-{page['index']:03d}.ocr.json"
    if output.exists():
        return {"book": folder.name, "page": page["index"], "cached": True}
    if not hasattr(LOCAL, "api"):
        LOCAL.api = PyTessBaseAPI(path=os.path.relpath(ROOT / "course_sources" / "tessdata"), lang="jpn_vert+jpn", oem=OEM.LSTM_ONLY, psm=PSM.AUTO)
    api = LOCAL.api
    image = Image.open(folder / page["images"][0]["file"])
    api.SetImage(image)
    text = api.GetUTF8Text()
    words = []
    iterator = api.GetIterator()
    if iterator is not None:
        while True:
            try:
                value = iterator.GetUTF8Text(RIL.WORD)
            except RuntimeError:
                value = ""  # Blank pages and non-text image regions.
            if value:
                words.append({"text": value, "box": iterator.BoundingBox(RIL.WORD), "confidence": round(iterator.Confidence(RIL.WORD), 2)})
            if not iterator.Next(RIL.WORD):
                break
    result = {"page": page["index"], "source_sha256": page["images"][0]["sha256"], "text": text, "words": words, "mean_confidence": api.MeanTextConf(), "review_status": "draft"}
    temporary = output.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(output)
    return {"book": folder.name, "page": page["index"], "words": len(words), "confidence": result["mean_confidence"]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    tasks = []
    for name in ["hanyu-intro", "hanyu-opening"]:
        folder = ROOT / "course_sources" / name
        index = json.loads((folder / "index.json").read_text(encoding="utf-8"))
        pages = index["pages"][:args.limit] if args.limit else index["pages"]
        tasks.extend((folder, page) for page in pages if page["images"])
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 6))) as pool:
        futures = [pool.submit(recognize, task) for task in tasks]
        for count, future in enumerate(as_completed(futures), 1):
            result = future.result()
            print(json.dumps({"done": count, "total": len(tasks), "seconds": round(time.monotonic()-start), **result}), flush=True)


if __name__ == "__main__":
    main()
