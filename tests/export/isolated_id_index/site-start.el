;;; site-start.el --- per-test Org ID index for batch exports  -*- lexical-binding: t -*-
;; Batch Emacs loads site-start.el from the load path at startup. The tests put
;; this folder first on EMACSLOADPATH, so every export they run keeps its Org ID
;; index in the file named by PAIRED_TEST_ORG_ID_LOCATIONS, not in the shared
;; batch index ~/.emacs.d/org-id-locations that latex_init.el names.
;; Org resolves an id: link through that index and adds every visited file to
;; it, so with the shared index an export of one test copy can link to another
;; copy, and a later production export can link to a test copy.
(with-eval-after-load "latex_init"
  (let ((index (getenv "PAIRED_TEST_ORG_ID_LOCATIONS")))
    (when (and index (not (string-empty-p index)))
      (setq org-id-locations-file index))))
