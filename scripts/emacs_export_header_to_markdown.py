#!/usr/bin/env python3

"""
Script to generate Markdown files from Emacs Org-mode headers
"""

import argparse
import os
import subprocess
import sys

def load_inputs():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org_file", type=str, required=True, help="Org-mode file with header to export")
    parser.add_argument("--node_id", type=str, required=True, help="ID of header to export")
    return parser.parse_args()

def main():
    args = load_inputs()
    generate_md_via_org(args.org_file, args.node_id)
    extracted_md_path = extract_md_path(args.org_file, args.node_id)
    print(f"Markdown exported to: {extracted_md_path}")

def generate_md_via_org(org_file, node_id):
    command = f'''/usr/local/bin/emacs --batch -l "${{HOME}}/repos/basecamp/emacs/latex_init.el" --eval "(progn
        (require 'org)
        (require 'org-id)
        (setq org-confirm-babel-evaluate nil)
        (find-file \\"{org_file}\\")
        (org-id-goto \\"{node_id}\\")
        (org-md-export-to-markdown nil t)
        (kill-emacs))"'''
    try:
        result = subprocess.run(command, check=True, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error: {e.stderr}")
        raise

def extract_md_path(org_file, node_id):
    command = f'''/usr/local/bin/emacs --batch -l "${{HOME}}/repos/basecamp/emacs/latex_init.el" --eval "(progn
        (require 'org)
        (require 'org-id)
        (find-file \\"{org_file}\\")
        (org-id-goto \\"{node_id}\\")
        (let ((result (org-entry-get nil \\"export_file_name\\")))
          (princ result)))"'''
    try:
        result = subprocess.run(command, check=True, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        export_base = result.stdout.strip().strip('"')
        if export_base.endswith(".pdf") or export_base.endswith(".tex"):
            export_base = os.path.splitext(export_base)[0]
        if export_base.startswith("./"):
            org_file_dir = os.path.dirname(os.path.abspath(org_file))
            export_base = os.path.join(org_file_dir, export_base[2:])
        md_path = export_base + ".md"
        return md_path
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error: {e.stderr}")
        raise

if __name__ == "__main__":
    main()
