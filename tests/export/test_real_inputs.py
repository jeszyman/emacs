"""Markdown regression on the sections whose org_update.sh runs this script.

Each org file is copied to a temporary directory; the baseline and the new script
export the same section from separate copies, and the outputs must be byte-identical
outside display equations. The baseline writes an equation environment as raw LaTeX
and the new script as a numbered $$ block (test_paired_export checks that block), so
both are replaced by one placeholder before the comparison.
"""

import re
import shutil
from pathlib import Path

import pytest

from conftest import BASELINE, RMETH_ORG, SCRIPT, run_export

HOME = Path.home()
INPUTS = [
    ("rmeth-readme", RMETH_ORG, "9f6d5e1e-f8bd-43f6-a4b5-a75f1d7b3b4f", "README.md"),
    ("rmeth-method", RMETH_ORG, "f731ab06-7b9a-44ad-a47d-4bcadf1fe4ba", "METHOD.md"),
    (
        "frag-readme",
        HOME / "repos/frag/frag.org",
        "339b69f6-6c09-4e9d-a2ec-27bdf5747163",
        "README.md",
    ),
    (
        "emseq-readme",
        HOME / "repos/emseq/emseq.org",
        "bda70cff-0713-4e32-8da1-ee83924b8f00",
        "README.md",
    ),
]

# ox-md puts \label{name} after the environment's first line, which for a
# one-line environment is after \end{equation}.
BASE_EQUATION = re.compile(
    r"\\begin\{equation\}.*?\\end\{equation\}(?:\n\\label\{[^}]*\})?", re.S
)
NEW_EQUATION = re.compile(
    r'(?:<a id="[^"]*"></a>\n\n)?^\$\$\n(?:(?!\$\$).)*?\\tag\{\d+\}\n\$\$$', re.S | re.M
)


def mask_equations(md):
    return NEW_EQUATION.sub("<equation>", BASE_EQUATION.sub("<equation>", md))


@pytest.mark.parametrize("name,org,node,out", INPUTS, ids=[i[0] for i in INPUTS])
def test_md_byte_identical(tmp_path, name, org, node, out):
    results = {}
    for side, script in (("base", BASELINE), ("new", SCRIPT)):
        d = tmp_path / side
        d.mkdir()
        shutil.copy(org, d / org.name)
        run_export(script, d, org.name, node, "md" if side == "new" else None)
        results[side] = mask_equations((d / out).read_text())
    assert results["new"] == results["base"]
