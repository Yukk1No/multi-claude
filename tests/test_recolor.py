"""Tests for src/linux/recolor.py - standard library only. Run: python3 -m unittest discover tests"""
import colorsys
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src" / "linux"))
import recolor

ORANGE, WHITE, CLEAR = (217, 119, 87, 255), (255, 255, 255, 255), (0, 0, 0, 0)


def synthetic_logo(size=32):
    """Orange square, white glyph in the middle, one transparent corner."""
    rows = [[ORANGE] * size for _ in range(size)]
    for y in range(12, 20):
        for x in range(12, 20):
            rows[y][x] = WHITE
    rows[0][0] = CLEAR
    return rows


class RecolorTest(unittest.TestCase):
    def test_background_takes_target_color(self):
        r, g, b, _ = recolor.recolor(synthetic_logo(), "1F4E8C")[4][4]
        h, _, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        self.assertAlmostEqual(h * 360, 214, delta=6)
        self.assertAlmostEqual(v, 0x8C / 255, delta=0.05)

    def test_glyph_stays_white(self):
        self.assertTrue(all(c > 240 for c in recolor.recolor(synthetic_logo(), "1F6F43")[16][16][:3]))

    def test_transparency_is_kept(self):
        self.assertEqual(recolor.recolor(synthetic_logo(), "1F6F43")[0][0][3], 0)

    def test_png_round_trip(self):
        rows = synthetic_logo()
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "x.png"
            recolor.write_png(path, 32, 32, rows)
            w, h, back = recolor.read_png(path)
        self.assertEqual((w, h), (32, 32))
        self.assertEqual(back, [list(map(tuple, row)) for row in rows])


if __name__ == "__main__":
    unittest.main()
