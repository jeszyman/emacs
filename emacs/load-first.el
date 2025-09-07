(add-to-list 'exec-path "/usr/local/bin")

;(cua-selection-mode t)
;(setq mark-even-if-inactive t) ;; Keep mark active even when buffer is inactive
;(transient-mark-mode 1) ;; Enable transient-mark-mode for visual selection
(scroll-bar-mode 'right) ;; Place scroll bar on the right side

(setq org-export-backends '(ascii html latex odt icalendar md org)) ; This variable needs to be set before org.el is loaded.
