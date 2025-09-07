emacsclient -e "(progn (find-file \"$1\") \
                       (org-id-goto \"$2\") \
                       (org-beamer-export-to-pdf nil t))"
