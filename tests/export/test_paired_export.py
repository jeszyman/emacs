"""Exports of the test document: Markdown regression and the paired HTML."""

import shutil
import subprocess
import sys

from conftest import BASELINE, CHECK, FIXTURE, FIXTURE_ID, SCRIPT, run_export


def copy_fixture(dest):
    shutil.copytree(FIXTURE, dest)
    return dest


def test_html_writer_styles_only_path_specific_rules():
    # Styling shared by every HTML document lives in the shared stylesheet
    # org.css, which the template's other HTML route also links. The writer's
    # own <style> keeps only what must differ on this route: Org numbers
    # captions here, so org.css's caption counters are switched off
    # (2026-10-13: three general rules sat here and the other route missed them).
    import re

    src = open(SCRIPT).read()
    block = re.search(
        r"org-html-head-extra \"<style[^>]*>(.*?)</style>", src, re.S
    ).group(1)
    rules = [r.strip() for r in block.strip().splitlines() if r.strip()]
    assert rules == ["caption::before, figcaption::before { content: none; }"], rules


def test_md_matches_baseline(tmp_path):
    base, new = copy_fixture(tmp_path / "base"), copy_fixture(tmp_path / "new")
    run_export(BASELINE, base, "proj.org", FIXTURE_ID)
    run_export(SCRIPT, new, "proj.org", FIXTURE_ID)
    assert (new / "METHOD.md").read_bytes() == (base / "METHOD.md").read_bytes()


def test_id_not_in_file_fails(tmp_path):
    d = copy_fixture(tmp_path / "proj")
    r = run_export(
        SCRIPT, d, "proj.org", "00000000-0000-4000-8000-000000000000", check=False
    )
    assert r.returncode != 0
    assert "is not in" in r.stdout + r.stderr


def export_both(tmp_path):
    d = copy_fixture(tmp_path / "proj")
    run_export(SCRIPT, d, "proj.org", FIXTURE_ID, "both")
    return d


def test_both_formats_pass_check(tmp_path):
    d = export_both(tmp_path)
    r = subprocess.run(
        [
            sys.executable,
            str(CHECK),
            str(d / "METHOD.md"),
            str(d / "METHOD.html"),
            "--expect-val",
            "3.1",
        ],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout
    assert (
        r.stdout.strip()
        == "OK figures=2 tables=2 bibliography=2 footnotes=1 equations=0 crossrefs=4"
    )


def test_both_md_still_matches_baseline(tmp_path):
    d = export_both(tmp_path)
    base = copy_fixture(tmp_path / "base")
    run_export(BASELINE, base, "proj.org", FIXTURE_ID)
    assert (d / "METHOD.md").read_bytes() == (base / "METHOD.md").read_bytes()


def test_repo_links_are_text_and_title_set(tmp_path):
    html = (export_both(tmp_path) / "METHOD.html").read_text()
    assert "<code>scripts/count.py</code>" in html
    assert 'href="scripts/' not in html and 'href="proj.org' not in html
    assert "Validation, Checks" in html and "the validation section" in html
    assert 'href="https://orgmode.org/"' in html
    assert "<title>proj Method: paired export test document</title>" in html


def test_duplicate_titles_get_distinct_anchors(tmp_path):
    html = (export_both(tmp_path) / "METHOD.html").read_text()
    assert 'id="notes"' in html and 'id="notes-1"' in html


def test_missing_image_fails_and_names_it(tmp_path):
    d = copy_fixture(tmp_path / "proj")
    (d / "resources/figures/demo.png").unlink()
    r = run_export(SCRIPT, d, "proj.org", FIXTURE_ID, "html", check=False)
    assert r.returncode != 0
    assert "demo.png" in r.stdout + r.stderr
    assert not (d / "METHOD.html").exists()


EQUATIONS = """\
*** Equations
The count in library \\(s\\) is [[eq-count]], and its rate is [[eq-rate]].

#+name: eq-count
\\begin{equation}
N_{s} = \\sum_{r \\in R_{s}} \\mathbf{1}\\left[ r \\in K \\right]
\\end{equation}

#+name: eq-rate
\\begin{equation}
A_{s} = \\frac{10^{6} \\, N_{s}}{W_{s}}
\\end{equation}

"""


def test_equations_numbered_in_both_formats(tmp_path):
    # A named equation environment is numbered in both files and a link to it
    # reads "Equation N"; the HTML writes MathML and loads no MathJax.
    d = copy_fixture(tmp_path / "proj")
    org = d / "proj.org"
    org.write_text(
        org.read_text().replace("*** References", EQUATIONS + "*** References", 1)
    )
    run_export(SCRIPT, d, "proj.org", FIXTURE_ID, "both")
    md, html = (d / "METHOD.md").read_text(), (d / "METHOD.html").read_text()
    assert "[Equation 1](#eq-count)" in md and "[Equation 2](#eq-rate)" in md
    assert (
        '<a id="eq-rate"></a>\n\n$$\nA_{s} = \\frac{10^{6} \\, N_{s}}{W_{s}} \\tag{2}\n$$'
        in md
    )
    assert '<a href="#eq-rate">Equation 2</a>' in html
    assert '<div id="eq-count" class="equation"><math display="block"' in html
    assert '<span class="equation-number">(2)</span></div>' in html
    assert '<math display="inline"' in html
    assert "MathJax-script" not in html and "\\begin{equation}" not in html
    r = subprocess.run(
        [sys.executable, str(CHECK), str(d / "METHOD.md"), str(d / "METHOD.html")],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout
    assert "equations=2" in r.stdout and "crossrefs=6" in r.stdout
