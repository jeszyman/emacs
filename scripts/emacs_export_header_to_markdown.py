#!/usr/bin/env python3

"""
Export one Org heading to Markdown for GitHub (--format md, the default), to one
self-contained HTML file for readers without GitHub (--format html), or to both.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

EMACS = "/usr/local/bin/emacs"
EMACS_INIT = os.path.expanduser("~/repos/latex/emacs/latex_init.el")
# The HTML export embeds this stylesheet with this embedding script. Tests and
# checks point them elsewhere with the environment variables.
ORG_CSS = os.environ.get(
    "EXPORT_ORG_CSS", os.path.expanduser("~/repos/science/resources/org.css")
)
INLINE_HTML = os.environ.get(
    "EXPORT_INLINE_HTML", os.path.expanduser("~/repos/science/resources/inline_html.py")
)


def load_inputs():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--org_file",
        type=str,
        required=True,
        help="Org-mode file with header to export",
    )
    parser.add_argument(
        "--node_id", type=str, required=True, help="ID of header to export"
    )
    parser.add_argument(
        "--format",
        choices=("md", "html", "both"),
        default="md",
        help="md: Markdown for GitHub; html: one self-contained HTML file; both",
    )
    return parser.parse_args()


def main():
    args = load_inputs()
    md_path = extract_md_path(args.org_file, args.node_id)
    if args.format in ("md", "both"):
        run_export(
            args.org_file,
            args.node_id,
            MD_OVERRIDES,
            "(org-md-export-to-markdown nil t)",
        )
        link_caption_words(md_path)
        table_captions_below(md_path)
        strip_style_tags(md_path)
        join_bibliography_numbers(md_path)
        print(f"Markdown exported to: {md_path}")
    if args.format in ("html", "both"):
        html_path = os.path.splitext(md_path)[0] + ".html"
        try:
            run_export(
                args.org_file,
                args.node_id,
                html_overrides(),
                "(org-html-export-to-html nil t)",
            )
            subprocess.run([sys.executable, INLINE_HTML, html_path], check=True)
            join_bibliography_numbers(html_path)
            check_self_contained(html_path)
        except BaseException:
            # After a failed export, no HTML file is left: a partial or older
            # copy could be sent to a reader as if it were current.
            if os.path.exists(html_path):
                os.remove(html_path)
            raise
        print(f"HTML exported to: {html_path}")


def join_bibliography_numbers(md_path):
    # A numeric csl style writes each entry's number and text as two <div>
    # blocks: GitHub shows them on two lines, and in HTML the number floats
    # left with no padding, so a two-digit number abuts the author
    # ("32.Altemose"). Join them into "N. text" in both outputs.
    with open(md_path) as f:
        text = f.read()
    text = re.sub(
        r'<div class="csl-left-margin">(.*?)</div><div class="csl-right-inline">(.*?)</div>',
        r"\1 \2",
        text,
        flags=re.S,
    )
    with open(md_path, "w") as f:
        f.write(text)


def strip_style_tags(md_path):
    # The csl bibliography starts with a <style> tag. GitHub removes the tag
    # but shows its CSS as text, so the tag is removed here.
    with open(md_path) as f:
        text = f.read()
    text = re.sub(r"<style>.*?</style>", "", text, flags=re.S)
    with open(md_path, "w") as f:
        f.write(text)


def table_captions_below(md_path):
    # Tables take the figure caption style: an italic "Table N: caption" line
    # under the table, in place of ox-html's <caption> above it.
    cap_re = re.compile(
        r'<caption[^>]*><span class="table-number">(Table \d+):</span>\s*(.*?)</caption>\s*',
        re.S,
    )

    def move(m):
        c = cap_re.search(m.group(0))
        if not c:
            return m.group(0)
        return (
            cap_re.sub("", m.group(0), count=1)
            + f"\n\n*{c.group(1)}: {' '.join(c.group(2).split())}*"
        )

    with open(md_path) as f:
        text = f.read()
    text = re.sub(r"<table\b.*?</table>", move, text, flags=re.S)
    with open(md_path, "w") as f:
        f.write(text)


def link_caption_words(md_path):
    # ox-md links only the number of a table or figure reference
    # ("Table [1](#x)"). Put the word inside the link: "[Table 1](#x)".
    with open(md_path) as f:
        text = f.read()
    text = re.sub(r"\b(Table|Figure) \[(\d+)\]\(#", r"[\1 \2](#", text)
    with open(md_path, "w") as f:
        f.write(text)


# Overrides loaded into the batch Emacs before either export.
# 1. Org gives each table or figure a random anchor (org-export-new-reference)
#    that changes on every export. An element with a #+name uses that name as
#    its anchor, at the target and in every link to it.
# 2. A heading's anchor is its CUSTOM_ID, else the slug GitHub gives the
#    rendered heading (lowercase, punctuation removed, spaces as hyphens,
#    -1, -2 on repeated titles in document order), so a link to a heading
#    lands on GitHub's own heading anchor.
# 3. A figure is a paragraph holding only an image, with a #+caption; figures
#    are numbered over figures only.
# 4. An id: link to a heading outside the export resolves to the file that
#    holds it; the title of that heading is read from the file.
# 5. A display equation is a LaTeX equation environment; equations are
#    numbered over equations only, and a link to one reads "Equation N".
SHARED_OVERRIDES = r"""
(require 'ox)
(require 'ox-html)
;; Acronyms and glossary terms (org-glossary), for a heading that opts in with a
;; #+print_glossary: keyword: a term defined under an Acronyms or Glossary
;; heading anywhere in the file is expanded at its first use in the exported
;; text, and the keyword prints the terms the export used. A heading without
;; the keyword exports as before, since org-glossary also strips every heading
;; named Glossary or Index from the export. Two org-glossary steps scan the
;; whole file with org-element-cache-map while the export copy is narrowed to
;; the subtree, and in Org 9.7 that scan restarts forever at the narrowed end
;; (2026-10-20); they run widened.
(defun paired-glossary-maybe ()
  "Load org-glossary when the subtree at point holds a #+print_glossary: keyword."
  (when (save-excursion
          (re-search-forward "^[ \t]*#\\+print_glossary:"
                             (save-excursion (org-end-of-subtree t t)) t))
    (require 'org-glossary)
    (setq org-glossary-toplevel-only nil)
    (dolist (f '(org-glossary--get-terms-cached org-glossary--strip-headings))
      (advice-add f :around
                  (lambda (orig &rest args) (save-restriction (widen) (apply orig args)))
                  '((name . paired-glossary-widen))))
    ;; Printed terms are description lists, like the notebook's own lists.
    (org-glossary-set-export-spec t t :definition-structure "- %d :: %v\n")
    ;; Only a term's first use links to its definition; later uses are plain
    ;; text (Markdown derives from the HTML backend and follows it).
    (org-glossary-set-export-spec 'html t
      :use "%t"
      :first-use "<a class=\"org-gls\" href=\"#gls.%K\" id=\"glsr.%K.%r\">%t</a>")
    (org-glossary-set-export-spec 'html 'acronym
      :first-use "%v (<a class=\"org-gls\" href=\"#gls.%K\" id=\"glsr.%K.%r\">%t</a>)")
    ;; org-glossary exports a term's text as a one-line paragraph: the HTML
    ;; backend wraps it in <p> ... </p> inside the sentence that uses it, and
    ;; under org-export-preserve-breaks (latex_init.el) the paragraph's final
    ;; newline becomes a <br /> before the "(ACRONYM)" of a first use
    ;; (2026-10-20). Both are removed from the exported term text.
    (dolist (f '(org-glossary--export-term org-glossary--export-term-str))
      (advice-add f :filter-return
                  (lambda (s)
                    (if (stringp s)
                        (string-trim
                         (replace-regexp-in-string
                          "\\(<br />\\|</p>\\)[ \t\n]*\\'" ""
                          (replace-regexp-in-string "\\`<p>[ \t\n]*" "" s)))
                      s))
                  '((name . paired-glossary-unwrap))))))
;; INFO carries the export's image rules; without it Org falls back to a
;; default list that has no svg.
(defun paired-figure-p (el info)
  (and (org-element-type-p el 'paragraph)
       (org-element-property :caption el)
       (org-html-standalone-image-p el info)))
(defun paired-figure-number (el info)
  (org-export-get-ordinal el info '(paragraph) #'paired-figure-p))
(defvar paired-heading-slugs nil)
(defun paired-plain-title (h)
  (let ((s (org-element-property :raw-value h)))
    (setq s (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" s))
    (replace-regexp-in-string "\\[\\[\\([^]]*\\)\\]\\]" "\\1" s)))
(defun paired-github-slug (s)
  (replace-regexp-in-string
   " " "-" (replace-regexp-in-string "[^[:alnum:] _-]" "" (downcase s))))
(defun paired-heading-slug (h info)
  (let ((tree (plist-get info :parse-tree)))
    (unless (eq (car paired-heading-slugs) tree)
      (let ((slugs (make-hash-table :test 'eq))
            (seen (make-hash-table :test 'equal)))
        (org-element-map tree 'headline
          (lambda (x)
            (let* ((base (paired-github-slug (paired-plain-title x)))
                   (n (gethash base seen 0)))
              (puthash x (if (= n 0) base (format "%s-%d" base n)) slugs)
              (puthash base (1+ n) seen)))
          info)
        (setq paired-heading-slugs (cons tree slugs))))
    (gethash h (cdr paired-heading-slugs))))
(defun paired-external-id-file (link info)
  "The file holding the heading an id: LINK names, when that heading is outside the export."
  (and (equal (org-element-property :type link) "id")
       (let ((dest (condition-case nil
                       (org-export-resolve-id-link link info)
                     (org-link-broken nil))))
         (and (stringp dest) dest))))
(defun paired-id-heading-title (link file)
  "The title of the heading in FILE that the id: LINK names, or nil."
  (let ((id (org-element-property :path link)))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (let ((p (org-find-entry-with-id id)))
         (when p (goto-char p) (org-get-heading t t t t)))))))
(advice-add 'org-export-get-reference :around
            (lambda (orig datum info)
              (or (if (org-element-type-p datum 'headline)
                      (or (org-element-property :CUSTOM_ID datum)
                          (paired-heading-slug datum info))
                    (org-element-property :name datum))
                  (funcall orig datum info))))
(defun paired-equation-p (el &optional _info)
  "Non-nil when EL is a LaTeX equation environment."
  (and (org-element-type-p el 'latex-environment)
       (string-match-p "\\`[ \t\n]*\\\\begin{equation}"
                       (org-element-property :value el))))
(defun paired-equation-number (el info)
  (org-export-get-ordinal el info '(latex-environment) #'paired-equation-p))
(defun paired-equation-body (el)
  "The math of the equation environment EL, without its begin and end lines."
  (string-trim
   (replace-regexp-in-string
    "\\\\end{equation}[ \t\n]*\\'" ""
    (replace-regexp-in-string "\\`[ \t\n]*\\\\begin{equation}" ""
                              (org-element-property :value el)))))
"""

# Markdown writer.
# 1. Footnotes are written as native Markdown footnotes ([^label] in the text,
#    "[^label]: text" at the end), which GitHub renders with links both ways.
#    ox-md's own footnotes link the reference by label (fn.label) but the
#    definition by number (fn.1), so a named footnote has two dead links.
#    A numeric or missing label uses the footnote number.
# 2. A figure is written as its anchor, the image, and a visible
#    "Figure N: caption" line; ox-md puts the caption only in the image's
#    hover title. A link to a figure or table reads "Figure N" / "Table N".
# 3. Links to .org files keep the .org path; a heading target becomes
#    GitHub's heading anchor.
# 4. A display equation is written as its anchor and a $$ block ending in
#    \tag{N}, which MathJax, GitHub's math renderer, prints as the number.
MD_WRITER = r"""
(require 'ox-md)
;; Links in tables go through ox-html, which rewrites a link to a .org file
;; as .html; the repository holds the .org file.
(setq org-html-link-org-files-as-html nil)
(advice-add 'org-md-link :around
            (lambda (orig link desc info)
              (let* ((par (org-element-parent-element link))
                     (dest (and (equal (org-element-property :type link) "fuzzy")
                                (condition-case nil
                                    (org-export-resolve-fuzzy-link link info)
                                  (org-link-broken nil))))
                     (id-file (paired-external-id-file link info)))
                (cond
                 ;; ox-md rewrites a link to a .org file as .md and drops a
                 ;; ::*Heading target; keep the .org path and turn the heading
                 ;; into GitHub's heading anchor.
                 ((and (equal (org-element-property :type link) "file")
                       (string-suffix-p ".org" (org-element-property :path link)))
                  (let* ((path (org-element-property :path link))
                         (opt (org-element-property :search-option link))
                         (anchor (if (and opt (string-prefix-p "*" opt))
                                     (concat "#" (paired-github-slug (substring opt 1)))
                                   "")))
                    (format "[%s](%s%s)" (or (org-string-nw-p desc) path) path anchor)))
                 ;; An id: link to a heading outside the export resolves to its
                 ;; file; link to that .org file at the heading's anchor.
                 (id-file
                  (let ((title (paired-id-heading-title link id-file))
                        (rel (file-relative-name
                              id-file (file-name-directory (plist-get info :input-file)))))
                    (format "[%s](%s%s)" (or (org-string-nw-p desc) rel) rel
                            (if title (concat "#" (paired-github-slug title)) ""))))
                 ((and dest (paired-equation-p dest info))
                  (format "[%s](#%s)"
                          (or (org-string-nw-p desc)
                              (format "Equation %d" (paired-equation-number dest info)))
                          (org-export-get-reference dest info)))
                 ;; A table reference reads "Table N", numbered as ox-html
                 ;; numbers table captions.
                 ((and dest (org-element-type-p dest 'table)
                       (org-element-property :caption dest))
                  (format "[%s](#%s)"
                          (or (org-string-nw-p desc)
                              (format "Table %d"
                                      (org-export-get-ordinal
                                       dest info nil #'org-html--has-caption-p)))
                          (org-export-get-reference dest info)))
                 ((and dest (paired-figure-p dest info))
                  (format "[%s](#%s)"
                          (or (org-string-nw-p desc)
                              (format "Figure %d" (paired-figure-number dest info)))
                          (org-export-get-reference dest info)))
                 ((and (paired-figure-p par info)
                       (org-html-inline-image-p link info))
                  (let ((cap (org-export-data (org-export-get-caption par) info)))
                    (format "<a id=\"%s\"></a>\n\n![%s](%s)\n\n*Figure %d: %s*"
                            (org-export-get-reference par info)
                            (replace-regexp-in-string "[][\n]" " " cap)
                            (org-element-property :path link)
                            (paired-figure-number par info) cap)))
                 (t (funcall orig link desc info))))))
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
(advice-add 'org-md-latex-environment :around
            (lambda (orig el contents info)
              (if (paired-equation-p el info)
                  (format "%s$$\n%s \\tag{%d}\n$$"
                          (if (org-element-property :name el)
                              (format "<a id=\"%s\"></a>\n\n"
                                      (org-export-get-reference el info))
                            "")
                          (paired-equation-body el)
                          (paired-equation-number el info))
                (funcall orig el contents info))))
"""

# The complete Emacs Lisp for a Markdown export. The crosslink skill's
# checker loads it by this name.
MD_OVERRIDES = SHARED_OVERRIDES + MD_WRITER

# HTML writer, for one file read away from the repository.
# 1. Table captions go under the table, as in the Markdown export. The page
#    has no Org default style or scripts and no validation link; the shared
#    report stylesheet org.css is linked here and embedded by inline_html.py.
# 2. org.css numbers captions with CSS counters. Org already writes the number
#    into each caption, and only Org's number matches the "Figure N" link
#    text, so the counters are switched off.
# 3. A link to a table or figure reads "Table N" / "Figure N". Links to files
#    in the repository and to headings in other files are kept as text, since
#    the reader has only the HTML file. Images stay images.
# 4. A wide table scrolls sideways inside the page; its caption stays under it.
# 5. Hovering a citation number shows its bibliography entry, and hovering a
#    "Table N" / "Figure N" link shows its caption (the link's title attribute).
# 6. Math is written as MathML by pandoc, which a browser renders without a
#    script, so the page loads no MathJax. A display equation is a block with
#    its number in parentheses beside it (laid out by org.css), and a link to
#    it reads "Equation N". The export fails when pandoc cannot convert a
#    formula.
HTML_WRITER = r"""
(setq org-html-table-caption-above nil
      org-html-head-include-default-style nil
      org-html-head-include-scripts nil
      org-html-validation-link nil
      org-html-postamble t
      org-html-postamble-format
      '(("en" "<hr/><p style=\"text-align:right; color:#888; font-size:0.9em;\">Last compiled %T</p>"))
      org-html-head "<link rel=\"stylesheet\" type=\"text/css\" href=\"@ORG_CSS@\"/>"
      org-html-head-extra "<style type=\"text/css\">
caption::before, figcaption::before { content: none; }
</style>
<script>
document.addEventListener('DOMContentLoaded', function () {
  var links = document.getElementsByTagName('a');
  for (var i = 0; i < links.length; i++) {
    var a = links[i], href = a.getAttribute('href');
    if (!href || href.charAt(0) !== '#') continue;
    var t = document.getElementById(href.slice(1));
    if (!t) continue;
    var num = t.querySelector('.figure-number');
    var src = t.closest('.csl-entry') || t.querySelector('caption') || (num && num.parentElement);
    if (src) a.title = src.textContent.replace(/\\s+/g, ' ').trim();
  }
});
</script>")
(defun paired-html-unlinked (desc path)
  "DESC, or PATH as code when DESC is empty: the text of a link the reader cannot open."
  (or (org-string-nw-p desc)
      (format "<code>%s</code>" (org-html-encode-plain-text path))))
(advice-add 'org-html-link :around
            (lambda (orig link desc info)
              (let* ((type (org-element-property :type link))
                     (dest (and (equal type "fuzzy")
                                (condition-case nil
                                    (org-export-resolve-fuzzy-link link info)
                                  (org-link-broken nil))))
                     (id-file (paired-external-id-file link info)))
                (cond
                 ((and dest (org-element-type-p dest 'table)
                       (org-element-property :caption dest))
                  (format "<a href=\"#%s\">%s</a>"
                          (org-export-get-reference dest info)
                          (or (org-string-nw-p desc)
                              (format "Table %d"
                                      (org-export-get-ordinal
                                       dest info nil #'org-html--has-caption-p)))))
                 ((and dest (paired-figure-p dest info))
                  (format "<a href=\"#%s\">%s</a>"
                          (org-export-get-reference dest info)
                          (or (org-string-nw-p desc)
                              (format "Figure %d" (paired-figure-number dest info)))))
                 ((and dest (paired-equation-p dest info))
                  (format "<a href=\"#%s\">%s</a>"
                          (org-export-get-reference dest info)
                          (or (org-string-nw-p desc)
                              (format "Equation %d" (paired-equation-number dest info)))))
                 ((and (equal type "file")
                       (not (org-export-inline-image-p
                             link (plist-get info :html-inline-image-rules))))
                  (paired-html-unlinked desc (org-element-property :path link)))
                 (id-file
                  (let ((title (paired-id-heading-title link id-file)))
                    (paired-html-unlinked
                     (or (org-string-nw-p desc)
                         (and title (org-html-encode-plain-text title)))
                     (org-element-property :path link))))
                 (t (funcall orig link desc info))))))
(advice-add 'org-html-table :filter-return
            (lambda (html) (concat "<div class=\"table-scroll\">\n" html "\n</div>")))
;; html, unlike verbatim, keeps math parsed (verbatim turns it back into text
;; before export, so a named equation loses its name), and unlike mathjax
;; adds no script.
(setq org-html-with-latex 'html)
(defun paired-mathml (tex display)
  "MathML for the TeX math TEX, as display math when DISPLAY is non-nil."
  (let ((out (with-temp-buffer
               (insert (format (if display "\\[%s\\]" "\\(%s\\)") tex))
               (call-process-region (point-min) (point-max) "pandoc" t '(t nil) nil
                                    "-f" "latex" "-t" "html" "--mathml")
               (buffer-string))))
    (unless (string-match-p "<math" out)
      (error "pandoc did not convert to MathML: %s" tex))
    (string-trim
     (replace-regexp-in-string "\\`[ \t\n]*<p>\\|</p>[ \t\n]*\\'" "" out))))
(advice-add 'org-html-latex-fragment :around
            (lambda (orig frag contents info)
              (let ((v (org-element-property :value frag)))
                (cond
                 ((string-prefix-p "\\(" v) (paired-mathml (substring v 2 -2) nil))
                 ((string-prefix-p "\\[" v) (paired-mathml (substring v 2 -2) t))
                 ((string-prefix-p "$$" v) (paired-mathml (substring v 2 -2) t))
                 ((string-prefix-p "$" v) (paired-mathml (substring v 1 -1) nil))
                 (t (funcall orig frag contents info))))))
(advice-add 'org-html-latex-environment :around
            (lambda (orig el contents info)
              (if (paired-equation-p el info)
                  (format "<div id=\"%s\" class=\"equation\">%s<span class=\"equation-number\">(%d)</span></div>"
                          (org-export-get-reference el info)
                          (paired-mathml (paired-equation-body el) t)
                          (paired-equation-number el info))
                (funcall orig el contents info))))
"""


def html_overrides():
    return SHARED_OVERRIDES + HTML_WRITER.replace("@ORG_CSS@", ORG_CSS)


def check_self_contained(html_path):
    # inline_html.py leaves a tag unchanged when its file is missing. A reader
    # who has only the HTML file would see a broken image or an unstyled page,
    # so the export fails and names what is missing.
    with open(html_path) as f:
        text = f.read()
    missing = [
        src
        for src in re.findall(r'<img\s[^>]*src="([^"]+)"', text)
        if not src.startswith("data:")
    ]
    missing += re.findall(r'<link\s+rel="stylesheet"[^>]*href="([^"]+)"', text)
    if missing:
        sys.exit(
            f"{html_path} is not self-contained; not embedded: {', '.join(missing)}"
        )


def elisp_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def find_heading_form(org_file, node_id):
    # The heading is looked up in ORG_FILE's own buffer. org-id-goto would use
    # the batch ID index, which can name another file holding the same ID (the
    # original, when this script runs on a copy).
    return (
        f"(find-file {elisp_string(org_file)}) "
        f"(goto-char (or (org-find-entry-with-id {elisp_string(node_id)}) "
        f'(error "ID %s is not in %s" {elisp_string(node_id)} {elisp_string(org_file)})))'
    )


# Review marks (a <~ ... ~> note to Claude, a <g{ ... }g> highlight of Claude's
# last changes) are shown by the user's Emacs config, which the batch export
# does not load, so a leftover mark would print literally. The export stops at
# the first mark in the heading's subtree and names its line.
REVIEW_MARK_CHECK = r"""(save-excursion
  (let ((end (save-excursion (org-end-of-subtree t t))))
    (when (re-search-forward "<~\\|<g{" end t)
      (error "Review mark left at line %d of %s: resolve every <~ ~> note and remove every <g{ }g> highlight before export"
             (line-number-at-pos) (buffer-file-name)))))"""


def run_export(org_file, node_id, overrides_el, export_call):
    with tempfile.NamedTemporaryFile("w", suffix=".el", delete=False) as f:
        f.write(overrides_el)
        overrides = f.name
    form = (
        f"(progn (require 'org) (require 'org-id) (setq org-confirm-babel-evaluate nil) "
        f"{find_heading_form(org_file, node_id)} {REVIEW_MARK_CHECK} (paired-glossary-maybe) {export_call} (kill-emacs))"
    )
    try:
        result = subprocess.run(
            [EMACS, "--batch", "-l", EMACS_INIT, "-l", overrides, "--eval", form],
            check=True,
            capture_output=True,
            text=True,
        )
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error: {e.stderr}")
        raise
    finally:
        os.unlink(overrides)


def extract_md_path(org_file, node_id):
    form = (
        f"(progn (require 'org) {find_heading_form(org_file, node_id)} "
        f'(princ (org-entry-get nil "export_file_name")))'
    )
    try:
        result = subprocess.run(
            [EMACS, "--batch", "-l", EMACS_INIT, "--eval", form],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error: {e.stderr}")
        raise
    export_base = result.stdout.strip().strip('"')
    if export_base.endswith(".pdf") or export_base.endswith(".tex"):
        export_base = os.path.splitext(export_base)[0]
    if export_base.startswith("./"):
        org_file_dir = os.path.dirname(os.path.abspath(org_file))
        export_base = os.path.join(org_file_dir, export_base[2:])
    return export_base + ".md"


if __name__ == "__main__":
    main()
