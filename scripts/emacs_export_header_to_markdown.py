#!/usr/bin/env python3

"""
Script to generate Markdown files from Emacs Org-mode headers
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

def load_inputs():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org_file", type=str, required=True, help="Org-mode file with header to export")
    parser.add_argument("--node_id", type=str, required=True, help="ID of header to export")
    return parser.parse_args()

def main():
    args = load_inputs()
    generate_md_via_org(args.org_file, args.node_id)
    extracted_md_path = extract_md_path(args.org_file, args.node_id)
    link_caption_words(extracted_md_path)
    print(f"Markdown exported to: {extracted_md_path}")

def link_caption_words(md_path):
    # ox-md links only the number of a table or figure reference
    # ("Table [1](#x)"). Put the word inside the link: "[Table 1](#x)".
    with open(md_path) as f:
        text = f.read()
    text = re.sub(r"\b(Table|Figure) \[(\d+)\]\(#", r"[\1 \2](#", text)
    with open(md_path, "w") as f:
        f.write(text)

# Overrides loaded into the batch Emacs before export.
# 1. Org gives each table or figure a random anchor (org-export-new-reference)
#    that changes on every export. An element with a #+name uses that name as
#    its anchor, at the target and in every link to it.
# 2. Footnotes are written as native Markdown footnotes ([^label] in the text,
#    "[^label]: text" at the end), which GitHub renders with links both ways.
#    ox-md's own footnotes link the reference by label (fn.label) but the
#    definition by number (fn.1), so a named footnote has two dead links.
#    A numeric or missing label uses the footnote number.
# 3. A heading's anchor is its CUSTOM_ID, else the slug GitHub gives the
#    rendered heading (lowercase, punctuation removed, spaces as hyphens,
#    -1, -2 on repeated titles in document order), so a link to a heading
#    lands on GitHub's own heading anchor.
MD_OVERRIDES = r'''
(require 'ox)
(require 'ox-md)
(defvar md-heading-slugs nil)
(defun md-plain-title (h)
  (let ((s (org-element-property :raw-value h)))
    (setq s (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" s))
    (replace-regexp-in-string "\\[\\[\\([^]]*\\)\\]\\]" "\\1" s)))
(defun md-github-slug (s)
  (replace-regexp-in-string
   " " "-" (replace-regexp-in-string "[^[:alnum:] _-]" "" (downcase s))))
(defun md-heading-slug (h info)
  (let ((tree (plist-get info :parse-tree)))
    (unless (eq (car md-heading-slugs) tree)
      (let ((slugs (make-hash-table :test 'eq))
            (seen (make-hash-table :test 'equal)))
        (org-element-map tree 'headline
          (lambda (x)
            (let* ((base (md-github-slug (md-plain-title x)))
                   (n (gethash base seen 0)))
              (puthash x (if (= n 0) base (format "%s-%d" base n)) slugs)
              (puthash base (1+ n) seen)))
          info)
        (setq md-heading-slugs (cons tree slugs))))
    (gethash h (cdr md-heading-slugs))))
(advice-add 'org-export-get-reference :around
            (lambda (orig datum info)
              (or (if (org-element-type-p datum 'headline)
                      (or (org-element-property :CUSTOM_ID datum)
                          (md-heading-slug datum info))
                    (org-element-property :name datum))
                  (funcall orig datum info))))
;; ox-md writes a heading anchor only for id: links and tables of contents.
;; A [[*Heading]] link also gets one, so the link works outside GitHub too.
(advice-add 'org-md--headline-referred-p :around
            (lambda (orig headline info)
              (or (funcall orig headline info)
                  (org-element-map (plist-get info :parse-tree) 'link
                    (lambda (link)
                      (and (equal (org-element-property :type link) "fuzzy")
                           (eq headline
                               (condition-case nil
                                   (org-export-resolve-fuzzy-link link info)
                                 (org-link-broken nil)))))
                    info t))))
(defun md-footnote-label (label n)
  (if (and label (not (string-match-p "\\`[0-9]+\\'" label)))
      label
    (number-to-string n)))
(advice-add 'org-html-footnote-reference :around
            (lambda (orig ref contents info)
              (if (org-export-derived-backend-p (plist-get info :back-end) 'md)
                  (format "[^%s]" (md-footnote-label
                                   (org-element-property :label ref)
                                   (org-export-get-footnote-number ref info)))
                (funcall orig ref contents info))))
(advice-add 'org-md--footnote-section :override
            (lambda (info)
              (let ((defs (org-export-collect-footnote-definitions info)))
                (when defs
                  (mapconcat
                   (lambda (d)
                     (format "[^%s]: %s"
                             (md-footnote-label (nth 1 d) (nth 0 d))
                             (replace-regexp-in-string
                              "\n\\(.\\)" "\n    \\1"
                              (org-trim (org-export-data (nth 2 d) info)))))
                   defs "\n\n")))))
'''

def generate_md_via_org(org_file, node_id):
    with tempfile.NamedTemporaryFile("w", suffix=".el", delete=False) as f:
        f.write(MD_OVERRIDES)
        overrides = f.name
    command = f'''/usr/local/bin/emacs --batch -l "${{HOME}}/repos/latex/emacs/latex_init.el" -l "{overrides}" --eval "(progn
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
    finally:
        os.unlink(overrides)

def extract_md_path(org_file, node_id):
    command = f'''/usr/local/bin/emacs --batch -l "${{HOME}}/repos/latex/emacs/latex_init.el" --eval "(progn
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
