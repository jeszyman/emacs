"""inline_html.py labels each embedded image with the MIME type of its suffix."""

import subprocess
import sys

from conftest import INLINE_HTML


def test_svg_png_jpeg_mime(tmp_path):
    (tmp_path / "a.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
    (tmp_path / "b.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    (tmp_path / "c.jpg").write_bytes(b"\xff\xd8\xff")
    page = tmp_path / "page.html"
    page.write_text('<img src="a.svg" /><img src="b.png" /><img src="c.jpg" />')
    subprocess.run([sys.executable, str(INLINE_HTML), str(page)], check=True)
    html = page.read_text()
    assert "data:image/svg+xml;base64," in html
    assert "data:image/png;base64," in html
    assert "data:image/jpeg;base64," in html
