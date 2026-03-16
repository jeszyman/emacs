# ============================================================
# AUTO-GENERATED — DO NOT EDIT DIRECTLY
# Edits will be overwritten on next org-babel tangle.
# 
# Source:  /home/jeszyman/repos/emacs/emacs.org
# Author:  Jeff Szymanski
# Tangled: 2026-03-16 12:34:25
# ============================================================

emacsclient -e "(progn (find-file \"$1\") \
                       (org-id-goto \"$2\") \
                       (org-beamer-export-to-pdf nil t))"
