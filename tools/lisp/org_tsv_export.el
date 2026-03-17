;; ============================================================
;; AUTO-GENERATED — DO NOT EDIT DIRECTLY
;; Edits will be overwritten on next org-babel tangle.
;; 
;; Source:  /home/jeszyman/repos/emacs/emacs.org
;; Author:  Jeffrey Szymanski
;; Tangled: 2026-03-17 09:19:58
;; ============================================================

(require 'org)

(defun my-tbl-export (name path)
"Search for table named `NAME` and export."
(interactive "s")
(show-all)
(let ((case-fold-search t))
  (if (search-forward-regexp (concat "#\\+NAME: +" name) nil t)
  (progn
    (next-line)
    (org-table-export (format "%s/%s.tsv" path name) "orgtbl-to-tsv")))))
