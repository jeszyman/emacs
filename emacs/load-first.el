(add-to-list 'exec-path "/usr/local/bin")

;; Puts bib.bib into loaded buffers
(find-file-noselect "~/repos/org/bib.bib")
;; Disable persistent org-element cache in daemon mode to prevent
;; bloated cache from blocking startup and starving the event loop
(when (daemonp)
  (setq org-element-cache-persistent nil))
(setq server-socket-dir (expand-file-name "server" user-emacs-directory))
(require 'server)
(unless (server-running-p) (server-start))
