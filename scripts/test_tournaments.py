"""Deterministic collector regressions; no network or account required."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import update_tournaments as collector

KIF = """先手：甲
後手：乙
開始日時：2026/09/08 09:00
棋戦：テスト
1 ７六歩(77) ( 0:01/0:01)
*Do not publish commentary.
2 ３四歩(33)
3 同　銀(31) (0:01/0:01)
4 投了
"""


class TournamentTests(unittest.TestCase):
    def test_cp932_utf8_and_bom_agree(self):
        self.assertEqual(collector.normalize_kif(KIF.encode("cp932")), collector.normalize_kif(KIF.encode("utf-8-sig")))

    def test_normalizes_same_square_without_losing_piece(self):
        result = collector.normalize_kif(KIF.encode())
        self.assertIn("3 同銀(31)", result["kif"])
        self.assertNotIn("commentary", result["kif"])
        self.assertEqual(result["plies"], 3)

    def test_comment_and_time_edits_keep_move_hash(self):
        a = collector.normalize_kif(KIF.encode())
        b = collector.normalize_kif(KIF.replace("Do not publish commentary.", "Revised commentary").replace("0:01", "0:02").encode())
        self.assertEqual(a["moves_sha256"], b["moves_sha256"])

    def test_rejects_unfinished_or_nonsequential_game(self):
        for text in (KIF.replace("4 投了", "4 中断"), KIF.replace("2 ３四", "8 ３四"), KIF.replace("先手：甲", "")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                collector.normalize_kif(text.encode())

    def test_discovery_filters_external_old_and_non_kif_urls(self):
        page = "http://live.shogi.or.jp/oui/"
        html = """<a href='kifu/67/oui202609080101.html'>valid</a>
        <a href='kifu/67/oui202609080101.html'>duplicate</a>
        <a href='kifu/61/oui202008010101.html'>old</a>
        <a href='https://evil.example/kifu/oui202609080101.html'>external</a>
        <a href='kifu/67/oui202609080101.html?redirect=x'>query</a>"""
        self.assertEqual(collector.discover(html, page, 2025), [page + "kifu/67/oui202609080101.html"])

    def test_urls_reject_credentials_ports_and_path_traversal(self):
        for url in ("http://live.shogi.or.jp@localhost/a.kif", "http://live.shogi.or.jp:80/oui/a.kif", "http://live.shogi.or.jp/oui/../a.kif", "file:///etc/passwd"):
            self.assertFalse(collector.official_url(url), url)

    def test_all_sources_down_preserves_previous_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "index.json"
            original = '{"games": [], "schema": 1}'
            path.write_text(original, encoding="utf-8")
            with patch.object(collector, "fetch", side_effect=OSError("offline")), self.assertRaises(RuntimeError):
                collector.update(path, 2025)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_record_index_does_not_republish_recent_moves(self):
        page = "http://live.shogi.or.jp/oui/kifu/67/oui202609080101.html"
        responses = [b'const KIF_FILE_NAME="/oui/kifu/67/oui202609080101.kif";', KIF.encode("cp932")]
        with patch.object(collector, "fetch", side_effect=responses):
            result = collector.record(page)
        self.assertNotIn("kif", result)
        self.assertNotIn("commentary", json.dumps(result))
        self.assertEqual(len(result["moves_sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
