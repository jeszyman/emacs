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
