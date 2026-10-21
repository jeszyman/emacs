"""A repository scaffolded from the biopipe template exports README and Method in both formats."""

import shutil
import subprocess
import sys

from conftest import CHECK, SCRIPT, TEMPLATE, run_export

README_ID = "aaaaaaaa-0000-4000-8000-00000000000a"
METHOD_ID = "aaaaaaaa-0000-4000-8000-00000000000b"


def test_scaffold_exports_both_formats(tmp_path):
    org = tmp_path / "demo.org"
    shutil.copy(TEMPLATE, org)
    # The substitution of the biopipe_org recipe in ~/repos/science/tools/sci-process-makefile.
    subprocess.run(
        [
            "sed",
            "-i",
            "s/__BIOPIPE_PROJECT__/demo/g; s/__BIOPIPE_YEAR__/2026/g; "
            "s/__BIOPIPE_DATE__/2026-10-10/g",
            str(org),
        ],
        check=True,
    )
    text = org.read_text()
    assert "METHOD_NODE=REPLACE_WITH_METHOD_ID" in text
    assert "--format html" in text and "METHOD.html export failed" in text
    assert "#+MACRO: val (eval" in text
    for name, node in (("README", README_ID), ("METHOD", METHOD_ID)):
        old = f":export_file_name: {name}\n"
        assert text.count(old) == 1, name
        text = text.replace(old, f"{old}:ID:       {node}\n")
    org.write_text(text)
    for name, node in (("README", README_ID), ("METHOD", METHOD_ID)):
        run_export(SCRIPT, tmp_path, "demo.org", node, "both")
        r = subprocess.run(
            [
                sys.executable,
                str(CHECK),
                str(tmp_path / f"{name}.md"),
                str(tmp_path / f"{name}.html"),
            ],
            capture_output=True,
            text=True,
        )
        assert r.returncode == 0, r.stdout
