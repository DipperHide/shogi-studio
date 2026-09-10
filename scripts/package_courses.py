"""Freeze a small manifest so exported course files can be verified in the app."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "godot/courses"
books = []
for name in ["hanyu-intro", "hanyu-opening"]:
    path = DIRECTORY / f"{name}.json"
    raw = path.read_bytes()
    book = json.loads(raw)
    assert book["schema"] == 1 and book["id"] == name and book["page_count"] == 227
    lessons = [lesson for chapter in book["chapters"] for lesson in chapter["lessons"]]
    assert len({chapter["id"] for chapter in book["chapters"]}) == len(book["chapters"])
    ids = [lesson["id"] for lesson in lessons]
    assert len(set(ids)) == len(ids), f"Duplicate lesson ID in {name}"
    for lesson in lessons:
        assert lesson["steps"] and lesson["pages"], f"Empty lesson: {lesson['id']}"
        assert all(type(page) is int and 0 <= page < 227 for page in lesson["pages"])
        for step in lesson["steps"]:
            assert all(type(page) is int and 0 <= page < 227 for page in step.get("source_pages", lesson["pages"]))
    pages = [entry["page"] for entry in book["coverage"]]
    assert sorted(pages) == list(range(227)), f"Incomplete page accounting in {name}"
    for entry in book["coverage"]:
        assert entry["status"] in {"authored_verified", "noninstructional_verified", "draft", "pending"}
        assert all(lesson_id in ids for lesson_id in entry["lesson_ids"]), entry
        if entry["status"] == "authored_verified":
            assert entry["lesson_ids"], f"Verified page {entry['page']} has no lesson"
            assert any(entry["page"] in lesson["pages"] for lesson in lessons
                       if lesson["id"] in entry["lesson_ids"]), f"Verified page {entry['page']} maps to unrelated lessons"
    steps = [step for lesson in lessons for step in lesson["steps"]]
    coverage = dict(Counter(entry["status"] for entry in book["coverage"]))
    books.append({
        "id": name, "file": f"{name}.json", "sha256": hashlib.sha256(raw).hexdigest(),
        "source_sha256": book["source_sha256"], "source_pages": book["page_count"],
        "lessons": len(lessons), "steps": len(steps),
        "interactive_steps": sum(step["kind"] != "text" for step in steps),
        "coverage": coverage,
        "complete": not any(coverage.get(status, 0) for status in ["draft", "pending"]),
    })
manifest = {"schema": 1, "generated_utc": datetime.now(timezone.utc).isoformat(), "books": books}
(DIRECTORY / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(manifest, ensure_ascii=True))
