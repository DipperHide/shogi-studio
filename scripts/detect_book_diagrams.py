"""Index printed grids without treating OCR output as reviewed lesson data.

Source pixels and inferred grid lines are retained for every candidate. This is
an authoring aid; partial boards, hands, labels and answers require review.
"""
from pathlib import Path
import argparse
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]

def runs(values):
    indices = np.flatnonzero(values)
    if not len(indices):
        return []
    groups = np.split(indices, np.flatnonzero(np.diff(indices) > 1) + 1)
    return [float(np.mean(group)) for group in groups]

def regular(lines):
    if not 3 <= len(lines) <= 10:
        return False
    gaps = np.diff(lines)
    return min(gaps) >= 18 and max(gaps) / min(gaps) < 1.14

def grid_lines(lines):
    # Movement arrows can contribute a line through the middle of a cell.
    # Keep only a complete uniformly spaced sequence spanning the outer border.
    if regular(lines):
        return lines
    if len(lines) < 3:
        return []
    for cells in range(9, 1, -1):
        step = (lines[-1] - lines[0]) / cells
        if step < 18:
            continue
        expected = np.linspace(lines[0], lines[-1], cells+1)
        chosen = [min(lines, key=lambda v: abs(v-e)) for e in expected]
        if all(abs(v-e) < max(2, step*.045) for v,e in zip(chosen,expected)):
            return chosen
    return []

def detect(path):
    rgb = np.asarray(Image.open(path).convert("RGB"))
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    ink = np.uint8(gray < 130) * 255
    horizontal = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((1, 60), np.uint8))
    vertical = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((60, 1), np.uint8))
    combined = cv2.bitwise_or(horizontal, vertical)
    combined = cv2.morphologyEx(combined, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    count, _, stats, _ = cv2.connectedComponentsWithStats(combined)
    diagrams = []
    for x, y, w, h, area in stats[1:]:
        if w < 100 or h < 100 or w > 1150 or h > 1500 or area < 900:
            continue
        xs = grid_lines(runs((vertical[y:y+h, x:x+w] > 0).sum(axis=0) > h * .68))
        ys = grid_lines(runs((horizontal[y:y+h, x:x+w] > 0).sum(axis=1) > w * .68))
        if not regular(xs) or not regular(ys):
            continue
        cell_ratio = np.median(np.diff(xs)) / np.median(np.diff(ys))
        if not .80 < cell_ratio < 1.20:
            continue
        diagrams.append({"rect": [int(x), int(y), int(w), int(h)],
                         "x_lines": [round(v+x, 2) for v in xs],
                         "y_lines": [round(v+y, 2) for v in ys],
                         "columns": len(xs)-1, "rows": len(ys)-1,
                         "review_status": "unreviewed"})
    return sorted(diagrams, key=lambda d: (d["rect"][1] // 130, d["rect"][0]))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--book", choices=["hanyu-intro", "hanyu-opening"])
    args = parser.parse_args()
    summaries = []
    for book in ([args.book] if args.book else ["hanyu-intro", "hanyu-opening"]):
        directory = ROOT / "course_sources" / book
        index = json.loads((directory / "index.json").read_text(encoding="utf-8"))
        report = {"book": book, "pages": [], "reviewed": False}
        for page in index["pages"]:
            source = directory / page["images"][0]["file"]
            diagrams = detect(source)
            for i, diagram in enumerate(diagrams):
                diagram["id"] = f"{book}-p{page['index']:03d}-d{i+1}"
            report["pages"].append({"page": page["index"], "source_sha256": page["images"][0]["sha256"], "diagrams": diagrams})
        (directory / "diagrams.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        found = sum(len(p["diagrams"]) for p in report["pages"])
        summaries.append({"book": book, "grids_detected": found, "pages_with_grids": sum(bool(p["diagrams"]) for p in report["pages"]), "all_pages": len(report["pages"]), "reviewed": False})
        # Compact contact sheets show missed/extra grids alongside original page numbers.
        selected = [p for p in report["pages"] if p["diagrams"]]
        out = ROOT / "review/app/complete/books"
        out.mkdir(exist_ok=True)
        for start in range(0, len(selected), 24):
            canvas = Image.new("RGB", (1440, 1700), "white")
            draw = ImageDraw.Draw(canvas)
            for n, page in enumerate(selected[start:start+24]):
                original = Image.open(directory / f"page-{page['page']:03d}-0.jpg").convert("RGB")
                marks = ImageDraw.Draw(original)
                for d in page["diagrams"]:
                    x, y, w, h = d["rect"]
                    marks.rectangle((x,y,x+w,y+h), outline="red", width=5)
                original.thumbnail((230, 370))
                x, y = (n % 6)*240, (n // 6)*425
                canvas.paste(original, (x,y+30))
                draw.text((x+8,y+8), f"{book} page {page['page']} ({len(page['diagrams'])})", fill="black")
            canvas.save(out / f"{book}-grids-{start:03d}.jpg")
    (ROOT / "review/app/complete/book-diagrams.json").write_text(json.dumps(summaries, indent=2), encoding="utf-8")
    print(json.dumps(summaries))

if __name__ == "__main__":
    main()
