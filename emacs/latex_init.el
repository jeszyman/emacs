;; Package Management Setup

(require 'package)

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; Ensure 'use-package' is installed
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

(defun add-to-load-path-if-exists (dir)
  "Add DIR and its subdirectories to the Emacs load-path if DIR exists."
  (if (file-directory-p dir)
      (let ((default-directory dir))
        (message "Adding %s and its subdirectories to load-path" dir)
        (normal-top-level-add-to-load-path '("."))
        (normal-top-level-add-subdirs-to-load-path))
    (message "Directory %s does not exist, skipping." dir)))

(add-to-load-path-if-exists "~/.emacs.d/lisp/")

(require 'org)
(require 'ox-latex)



(setq org-babel-default-header-args '(
				      (:comments . "no")
				      (:mkdirp . "yes")
				      (:padline . "no")
				      (:results . "silent")
                                      (:cache . "no")
                                      (:eval . "never")
                                      (:exports . "none")
                                      (:noweb . "yes")
                                      (:tangle . "no")
				      ))

;; the below as nil fucks of export of inline code
(setq org-export-babel-evaluate t)
;; https://emacs.stackexchange.com/questions/23982/cleanup-org-mode-export-intermediary-file/24000#24000


(setq-default cache-long-scans nil)
(setq org-export-with-broken-links t)
(setq org-export-allow-bind-keywords t)

(setq org-export-with-sub-superscripts nil
      org-export-headline-levels 2
      org-export-with-toc nil
      org-export-with-section-numbers nil
      org-export-with-tags nil
      org-export-with-todo-keywords nil)
(require 'ox-latex)

(customize-set-value 'org-latex-with-hyperref nil)

(setq org-latex-logfiles-extensions (quote ("auto" "lof" "lot" "tex~" "aux" "idx" "log" "out" "toc" "nav" "snm" "vrb" "dvi" "fdb_latexmk" "blg" "brf" "fls" "entoc" "ps" "spl" "bbl")))

(add-to-list 'org-latex-packages-alist '("" "listings"))
(add-to-list 'org-latex-packages-alist '("" "color"))
(setq org-latex-caption-above nil)

(setq org-latex-remove-logfiles t)

(add-to-list 'org-latex-packages-alist '("" "listingsutf8"))
(setq org-latex-src-block-backend 'minted)

(setq org-latex-pdf-process
      '("pdflatex -shell-escape -interaction nonstopmode -output-directory %o %f"
    "bibtex %b"
    "pdflatex -shell-escape -interaction nonstopmode -output-directory %o %f"
    "pdflatex -shell-escape -interaction nonstopmode -output-directory %o %f"))


(setq org-export-preserve-breaks t)

(defun org-plain-follow (id _)
  "Follow a plain link as if it were an ID link."
  (interactive "sOrg ID: ")
  (org-id-open id nil))

(defun org-plain-export (link description format info)
  "Exports a plain link.
   - For 'org' format (internal Org buffer display), show full link.
   - For final external exports (HTML, LaTeX, ASCII), show only the description."
  ;; 'link' is the path part (e.g., "5827ecc7-04d7-4af4-8844-4e68d1b38aca")
  ;; 'description' is the label (e.g., "No social media")
  (pcase format
    ;; If the format is 'org' (for internal Org conversion/display,
    ;; typically what org-babel uses for :results table)
    ('org
     (format "[[plain:%s][%s]]" link description)) ; Reconstruct the full Org link

    ;; For standard export backends (HTML, LaTeX, ASCII)
    ((or 'html 'latex 'ascii)
     (or description link)) ; Return only the description (label), or link if no description

    ;; For any other format (fallback), just return the description or link
    (_ (or description link))))

(org-link-set-parameters "plain"
                         :follow #'org-plain-follow
                         :complete #'org-id-complete ; Optional, but good for consistency
                         :export #'org-plain-export  ; Point to this refined export function
                         :face 'org-link) ; Optional: Style the link like other Org links

(provide 'ol-plain)

(with-eval-after-load 'org
  (require 'ol-plain))
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes '("empty"
                                    "\\documentclass{article}
\\newcommand\\foo{bar}
[NO-DEFAULT-PACKAGES]
[NO-PACKAGES]"
                                    ("\\section{%s}" . "\\section*{%s}")
                                    ("\\subsection{%s}" . "\\subsection*{%s}")
                                    ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                                    ("\\paragraph{%s}" . "\\paragraph*{%s}")
                                    ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))
; ---   Org-ref   --- ;
; ------------------- ;


;(setq org-ref-default-bibliography (variable 'my-bibtex-bibliography))

; ---   Ox-extra   --- ;
; -------------------- ;

(add-to-list 'load-path "~/.emacs.d/elpa/org-contrib-0.4.2/")
(require 'ox-extra)
(ox-extras-activate '(ignore-headlines))
(ox-extras-activate '(latex-header-blocks ignore-headlines))


;;;;;;;;;;;;;;;;;;;;;;;;;
;;;   Miscellaneous   ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package helm-bibtex
  :ensure t)

(use-package ivy-bibtex
  :ensure t)

(use-package pdf-tools
  :ensure t)
