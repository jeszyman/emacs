#!/usr/bin/env python3
"""Check that a Markdown and an HTML export of one Org heading carry the same content.

Usage: check_paired_export.py MD_FILE HTML_FILE [--expect-val VALUE]

Checks:
  1  an in-page link (#x) with no anchor x, in either file
  2  different numbers of captioned figures, captioned tables, bibliography
     entries or footnotes in the two files
  3  different ordered lists of "Figure N" / "Table N" link texts
  4  an HTML "Figure N" / "Table N" link whose target caption has another number
  5  the HTML's last caption::before or figcaption::before rule does not set
     content: none (the stylesheet would print a second number)
  6  an image that is not embedded, or an external stylesheet or script
  7  an href, src or data attribute in the HTML that is not #, data:, http(s): or
     mailto: (a link a reader of the single file cannot open)
  8  the expected value missing from either file
Each failure prints "FAIL <check> <message>" and the exit status is 1. On success the
script prints the HTML's counts and exits 0.
"""
import argparse
import re
import sys
from html.parser import HTMLParser

OPENABLE = ("#", "data:", "http://", "https://", "mailto:")
XREF = re.compile(r"^(Figure|Table) (\d+)$")
MD_XREF = re.compile(
    r"\[(Figure|Table) (\d+)\]\(#[^)]*\)|<a href=\"#[^\"]*\">(Figure|Table) (\d+)</a>"
)


class Page(HTMLParser):
    """Ids, link attributes, anchor texts, images, stylesheets, scripts and style text."""

    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.attrs = []
        self.anchors = []
        self.images = []
        self.stylesheets = []
        self.script_srcs = []
        self.styles = []
        self.text = []
        self._open = []
        self._in_style = False
        self.feed(text)
        self.close()

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if "id" in a:
            self.ids.add(a["id"])
        for key in ("href", "src", "data"):
            if key in a:
                self.attrs.append((tag, key, a[key]))
        if tag == "img":
            self.images.append(a.get("src", ""))
        elif tag == "link" and "stylesheet" in a.get("rel", ""):
            self.stylesheets.append(a.get("href", ""))
        elif tag == "script" and a.get("src"):
            self.script_srcs.append(a["src"])
        elif tag == "style":
            self._in_style = True
        elif tag == "a":
            self._open.append([a.get("href", ""), ""])

    def handle_endtag(self, tag):
        if tag == "style":
            self._in_style = False
        elif tag == "a" and self._open:
            href, text = self._open.pop()
            self.anchors.append((href, " ".join(text.split())))

    def handle_data(self, data):
        if self._in_style:
            self.styles.append(data)
            return
        for anchor in self._open:
            anchor[1] += data
        self.text.append(data)


def github_slug(text):
    """GitHub's heading anchor: lowercase, punctuation removed, spaces as hyphens."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^\w\- ]", "", text).replace(" ", "-")


def md_anchors(md, page):
    ids = set(page.ids)
    seen = {}
    for m in re.finditer(r"^#{1,6} (.+?)\s*$", md, re.M):
        base = github_slug(m.group(1))
        n = seen.get(base, 0)
        ids.add(base if n == 0 else f"{base}-{n}")
        seen[base] = n + 1
    return ids


def md_counts(md):
    return {
        "figures": len(re.findall(r"^\*Figure \d+: ", md, re.M)),
        "tables": len(re.findall(r"^\*Table \d+: ", md, re.M)),
        "bibliography": md.count('class="csl-entry"'),
        "footnotes": len(re.findall(r"^\[\^[^\]]+\]: ", md, re.M)),
    }


def html_counts(html):
    return {
        "figures": html.count('class="figure-number"'),
        "tables": html.count('class="table-number"'),
        "bibliography": html.count('class="csl-entry"'),
        "footnotes": html.count('class="footdef"'),
    }


def caption_number(html, target, kind):
    """The number in the caption of the figure or table whose id is TARGET, or None."""
    t = re.escape(target)
    if kind == "Figure":
        m = re.search(rf'<div id="{t}" class="figure">(.*?)</div>', html, re.S)
        n = m and re.search(r'class="figure-number">Figure (\d+):', m.group(1))
    else:
        m = re.search(rf'<table id="{t}"[^>]*>(.*?)</table>', html, re.S)
        n = m and re.search(r'class="table-number">Table (\d+):', m.group(1))
    return int(n.group(1)) if n else None


def last_rule_body(css, selector_re):
    body = None
    for m in re.finditer(r"([^{}]+)\{([^}]*)\}", css):
        if re.search(selector_re, m.group(1)):
            body = m.group(2)
    return body


def check(md_text, html_text, expect_val=None):
    failures = []
    md_page, page = Page(md_text), Page(html_text)

    # 1
    md_ids = md_anchors(md_text, md_page)
    md_links = re.findall(r"\]\(#([^)]+)\)", md_text) + [
        h[1:] for h, _ in md_page.anchors if h.startswith("#")
    ]
    for x in md_links:
        if x not in md_ids:
            failures.append((1, f"Markdown link #{x} has no anchor"))
    for h, _ in page.anchors:
        if h.startswith("#") and h[1:] not in page.ids:
            failures.append((1, f"HTML link {h} has no anchor"))

    # 2
    mc, hc = md_counts(md_text), html_counts(html_text)
    for key in mc:
        if mc[key] != hc[key]:
            failures.append((2, f"{key}: Markdown {mc[key]}, HTML {hc[key]}"))

    # 3
    md_xrefs = [f"{m[0] or m[2]} {m[1] or m[3]}" for m in MD_XREF.findall(md_text)]
    html_xrefs = [
        (h, t) for h, t in page.anchors if h.startswith("#") and XREF.match(t)
    ]
    if md_xrefs != [t for _, t in html_xrefs]:
        failures.append(
            (
                3,
                f"cross-references differ: Markdown {md_xrefs}, "
                f"HTML {[t for _, t in html_xrefs]}",
            )
        )

    # 4
    for h, t in html_xrefs:
        kind, n = XREF.match(t).groups()
        if caption_number(html_text, h[1:], kind) != int(n):
            failures.append(
                (
                    4,
                    f"link '{t}' to {h}: caption shows "
                    f"{caption_number(html_text, h[1:], kind)}",
                )
            )

    # 5
    css = re.sub(r"/\*.*?\*/", "", "\n".join(page.styles), flags=re.S)
    for name, sel in (
        ("caption::before", r"(?<![\w-])caption::before"),
        ("figcaption::before", r"figcaption::before"),
    ):
        body = last_rule_body(css, sel)
        if body is not None and not re.search(r"content\s*:\s*none", body):
            failures.append((5, f"last {name} rule does not set content: none"))

    # 6
    for src in page.images:
        if not src.startswith("data:"):
            failures.append((6, f"image not embedded: {src}"))
    for href in page.stylesheets:
        failures.append((6, f"external stylesheet: {href}"))
    for src in page.script_srcs:
        failures.append((6, f"external script: {src}"))

    # 7
    for tag, key, value in page.attrs:
        if not value.startswith(OPENABLE):
            failures.append(
                (7, f'<{tag} {key}="{value}"> cannot be opened from the file')
            )

    # 8
    if expect_val is not None:
        if expect_val not in md_text:
            failures.append((8, f"{expect_val} not in Markdown"))
        if expect_val not in "".join(page.text):
            failures.append((8, f"{expect_val} not in HTML text"))

    counts = dict(hc, crossrefs=len(html_xrefs))
    return failures, counts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("md")
    ap.add_argument("html")
    ap.add_argument("--expect-val")
    args = ap.parse_args()
    with open(args.md) as f:
        md = f.read()
    with open(args.html) as f:
        html = f.read()
    failures, counts = check(md, html, args.expect_val)
    for n, msg in failures:
        print(f"FAIL {n} {msg}")
    if failures:
        sys.exit(1)
    print("OK " + " ".join(f"{k}={v}" for k, v in counts.items()))


if __name__ == "__main__":
    main()
