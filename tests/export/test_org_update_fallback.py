"""A failed METHOD.html export in org_update.sh does not stop the Markdown exports."""

import re
import shutil
import subprocess

from conftest import INLINE_HTML, ORG_UPDATE, RMETH_ORG, SCRIPT, isolated_env


def test_html_failure_does_not_stop_markdown(tmp_path):
    d = tmp_path / "rmeth"
    d.mkdir()
    shutil.copy(RMETH_ORG, d / "rmeth.org")
    shutil.copytree(
        RMETH_ORG.parent / "resources" / "figures", d / "resources" / "figures"
    )
    func = re.search(
        r"^update_exports\(\) \{.*?^\}", ORG_UPDATE.read_text(), re.S | re.M
    ).group(0)
    script = f"set -euo pipefail\n{func}\nupdate_exports\necho AFTER_EXPORTS\n"
    env = isolated_env(
        tmp_path / "org-id-locations",
        REPO_DIR=str(d),
        README_ORG=str(d / "rmeth.org"),
        README_NODE="9f6d5e1e-f8bd-43f6-a4b5-a75f1d7b3b4f",
        METHOD_NODE="f731ab06-7b9a-44ad-a47d-4bcadf1fe4ba",
        README_EXPORT=str(SCRIPT),
        EXPORT_ORG_CSS="/nonexistent/org.css",
        EXPORT_INLINE_HTML=str(INLINE_HTML),
    )
    r = subprocess.run(
        ["bash", "-c", script], env=env, capture_output=True, text=True, timeout=3600
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "METHOD.html export failed" in r.stdout
    assert "AFTER_EXPORTS" in r.stdout
    assert (d / "README.md").exists() and (d / "METHOD.md").exists()
