;; ============================================================
;; AUTO-GENERATED — DO NOT EDIT DIRECTLY
;; Edits will be overwritten on next org-babel tangle.
;; 
;; Source:  /home/jeszyman/repos/emacs/emacs.org
;; Author:  Jeffrey Szymanski
;; Tangled: 2026-03-14 15:15:34
;; ============================================================

(add-to-list 'exec-path "/usr/local/bin")

;; Puts bib.bib into loaded buffers
(find-file-noselect "~/repos/org/bib.bib")
(setq server-socket-dir (expand-file-name "server" user-emacs-directory))
(require 'server)
(unless (server-running-p) (server-start))
