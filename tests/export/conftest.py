"""Paths and the export runner shared by the paired-export tests.

The tests run in two layouts: the staging folder dev/method-html-export/tests/ of an
rmeth worktree, and the installed folder ~/repos/emacs/tests/export/. Each path is the
first candidate that exists.

Every export a test runs gets its own empty Org ID index (isolated_env), so an id:
link resolves to the copy being exported, as it does to the original in production,
and no test writes temporary paths into the shared batch index.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()


def first_existing(*candidates):
    for c in candidates:
        if Path(c).exists():
            return Path(c)
    raise FileNotFoundError(f"none of {candidates} exists")


SCRIPT = first_existing(
    HERE.parent / "emacs_export_header_to_markdown.py",
    HOME / "repos/emacs/scripts/emacs_export_header_to_markdown.py",
)
INLINE_HTML = first_existing(
    HERE.parent / "inline_html.py", HOME / "repos/science/resources/inline_html.py"
)
TEMPLATE = first_existing(
    HERE.parent / "template" / "__BIOPIPE_PROJECT__.org",
    HOME / "repos/science/resources/biopipe-template/__BIOPIPE_PROJECT__.org",
)
ORG_UPDATE = first_existing(
    HERE.parent / "patches" / "rmeth" / "org_update.sh",
    HOME / "repos/rmeth/tools/shell/org_update.sh",
)
RMETH_ORG = first_existing(
    HERE.parents[2] / "rmeth.org", HOME / "repos/rmeth/rmeth.org"
)
BASELINE = HERE / "baseline_export_header_to_markdown.py"
CHECK = HERE / "check_paired_export.py"
FIXTURE = HERE / "fixture"
FIXTURE_ID = "11111111-2222-4333-8444-555555555555"
ID_INDEX_SITE = HERE / "isolated_id_index"


def isolated_env(index_file, **extra):
    """The environment for a batch export whose Org ID index is INDEX_FILE.

    isolated_id_index/site-start.el, first on EMACSLOADPATH, points Org at
    INDEX_FILE after latex_init.el has named the shared batch index.
    """
    load_path = str(ID_INDEX_SITE) + os.pathsep + os.environ.get("EMACSLOADPATH", "")
    return dict(
        os.environ,
        EMACSLOADPATH=load_path,
        PAIRED_TEST_ORG_ID_LOCATIONS=str(index_file),
        **extra,
    )


def run_export(script, workdir, org_name, node_id, fmt=None, env=None, check=True):
    """Run an export script on WORKDIR/ORG_NAME with WORKDIR as the working directory.

    The script writes its output beside the org file and post-processes the path
    relative to the working directory, so both must be WORKDIR. The run starts
    from an empty Org ID index of its own.
    """
    cmd = [
        sys.executable,
        str(script),
        "--org_file",
        str(Path(workdir) / org_name),
        "--node_id",
        node_id,
    ]
    if fmt:
        cmd += ["--format", fmt]
    with tempfile.TemporaryDirectory() as index_dir:
        full_env = isolated_env(
            Path(index_dir) / "org-id-locations",
            EXPORT_INLINE_HTML=str(INLINE_HTML),
            **(env or {}),
        )
        result = subprocess.run(
            cmd, cwd=workdir, capture_output=True, text=True, env=full_env, timeout=1800
        )
    if check:
        assert result.returncode == 0, result.stdout + result.stderr
    return result
