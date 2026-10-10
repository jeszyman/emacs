"""Each check of check_paired_export fails on its own defect and on no other."""

from check_paired_export import check

GOOD_MD = """# Overview

See [Figure 1](#fig-a) and [Table 1](#tab-a), cited <a href="#citeproc_bib_item_1">1</a>.[^n]

<a id="fig-a"></a>

![A figure.](resources/figures/a.svg)

*Figure 1: A figure.*

<table id="tab-a">
<tr><td>1</td></tr>
</table>

*Table 1: A table.*

# References

<div class="csl-bib-body">
<div class="csl-entry"><a id="citeproc_bib_item_1"></a>1. Alpha.</div>
</div>

Value 3.1.

[^n]: A note.
"""

ORG_CSS_STYLE = (
    '<style type="text/css">table { counter-increment: table; }\n'
    'caption::before { content: "Table " counter(table) ". "; font-weight: bold; }\n'
    'figcaption::before { content: "Figure " counter(figure) ". "; }</style>'
)
NONE_STYLE = '<style type="text/css">caption::before, figcaption::before { content: none; }</style>'

GOOD_HTML = """<html><head>
ORG_CSS
NONE
</head><body>
<h2 id="overview">Overview</h2>
<p>See <a href="#fig-a">Figure 1</a> and <a href="#tab-a">Table 1</a>, cited <a href="#citeproc_bib_item_1">1</a>.<sup><a id="fnr.n" class="footref" href="#fn.n">1</a></sup></p>
<div id="fig-a" class="figure">
<p><img src="data:image/svg+xml;base64,AAAA" alt="a.svg" /></p>
<p><span class="figure-number">Figure 1: </span>A figure.</p>
</div>
<div class="table-scroll"><table id="tab-a">
<caption class="t-bottom"><span class="table-number">Table 1:</span> A table.</caption>
<tr><td>1</td></tr>
</table></div>
<div class="csl-bib-body"><div class="csl-entry"><a id="citeproc_bib_item_1"></a>1. Alpha.</div></div>
<p>Value 3.1.</p>
<div id="footnotes"><div class="footdef"><sup><a id="fn.n" class="footnum" href="#fnr.n">1</a></sup> <div class="footpara"><p class="footpara">A note.</p></div></div></div>
<p><a href="https://orgmode.org/">Org</a></p>
</body></html>
""".replace(
    "ORG_CSS", ORG_CSS_STYLE
).replace(
    "NONE", NONE_STYLE
)


def failed(md, html, val=None):
    return {n for n, _ in check(md, html, val)[0]}


def test_good_pair_passes_with_counts():
    failures, counts = check(GOOD_MD, GOOD_HTML, "3.1")
    assert failures == []
    assert counts == {
        "figures": 1,
        "tables": 1,
        "bibliography": 1,
        "footnotes": 1,
        "crossrefs": 2,
    }


def test_1_md_link_without_anchor():
    assert failed(GOOD_MD + "\n[x](#nowhere)\n", GOOD_HTML) == {1}


def test_1_html_link_without_anchor():
    html = GOOD_HTML.replace("</body>", '<a href="#nowhere">x</a></body>')
    assert failed(GOOD_MD, html) == {1}


def test_1_md_heading_slug_is_an_anchor():
    assert (
        failed(GOOD_MD + "\n[o](#overview)\n# Overview\n[o2](#overview-1)\n", GOOD_HTML)
        == set()
    )


def test_2_count_mismatch():
    assert failed(GOOD_MD + "\n*Figure 2: Extra.*\n", GOOD_HTML) == {2}


def test_3_crossref_order_differs():
    md = GOOD_MD.replace(
        "See [Figure 1](#fig-a) and [Table 1](#tab-a)",
        "See [Table 1](#tab-a) and [Figure 1](#fig-a)",
    )
    assert failed(md, GOOD_HTML) == {3}


def test_4_caption_number_differs_from_link():
    html = GOOD_HTML.replace("Figure 1: </span>", "Figure 2: </span>")
    assert failed(GOOD_MD, html) == {4}


def test_5_counter_rule_after_none_rule():
    html = GOOD_HTML.replace(
        ORG_CSS_STYLE + "\n" + NONE_STYLE, NONE_STYLE + "\n" + ORG_CSS_STYLE
    )
    assert failed(GOOD_MD, html) == {5}


def test_6_and_7_image_not_embedded():
    html = GOOD_HTML.replace(
        "data:image/svg+xml;base64,AAAA", "resources/figures/a.svg"
    )
    assert failed(GOOD_MD, html) == {6, 7}


def test_6_external_script():
    html = GOOD_HTML.replace(
        "</head>", '<script src="https://cdn.example/x.js"></script></head>'
    )
    assert failed(GOOD_MD, html) == {6}


def test_7_relative_link():
    html = GOOD_HTML.replace("</body>", '<a href="config/x.yaml">x</a></body>')
    assert failed(GOOD_MD, html) == {7}


def test_7_object_data():
    html = GOOD_HTML.replace("</body>", '<object data="a.svg"></object></body>')
    assert failed(GOOD_MD, html) == {7}


def test_8_val_missing():
    assert failed(GOOD_MD, GOOD_HTML, "9.9") == {8}
