

;; Regression test, run in the live daemon: a failing ~org-glossary-mode~ must not stop ~org-mode-hook~ before ~global-font-lock-mode-enable-in-buffer~ runs, or org buffers lose syntax highlighting on every open and auto-revert.

;; #+name: org-glossary-hook-test

;;; org-glossary-hook-test.el --- live-daemon ERT test  -*- lexical-binding: t; -*-
;; Run: emacsclient --socket-name ~/.emacs.d/server/server --eval
;;   '(progn (load-file "~/repos/emacs/tests/org-glossary-hook-test.el")
;;           (ert-stats-completed-unexpected (ert-run-tests-batch "jg/org-glossary")))'
;; A result of 0 means pass.
(require 'ert)
(require 'cl-lib)

(ert-deftest jg/org-glossary-error-keeps-font-lock ()
  "An error from `org-glossary-mode' leaves font-lock on in a visited org file."
  (should (memq #'jg/org-glossary-mode-maybe (default-value 'org-mode-hook)))
  (let ((file (make-temp-file "glossary-hook-" nil ".org" "* Heading\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'org-glossary-mode)
                   (lambda (&rest _) (signal 'args-out-of-range '(90 103)))))
          (let ((buf (find-file-noselect file)))
            (unwind-protect
                (with-current-buffer buf
                  (should (derived-mode-p 'org-mode))
                  (should font-lock-mode))
              (kill-buffer buf))))
      (delete-file file))))

(ert-deftest jg/org-glossary-scan-skips-empty-nested ()
  "The work.org scanner emits no source for a glossary heading holding an empty
nested glossary-type heading, which would crash collection under
`org-glossary-toplevel-only' nil; a sibling heading with terms is still emitted."
  (let ((file (make-temp-file
               "glossary-scan-" nil ".org"
               (concat "* Acronyms\n- CTF :: Children's Tumor Foundation\n"
                       "** Glossary\n"
                       "* Glossary\n- cfDNA :: cell-free DNA\n"))))
    (unwind-protect
        (should (equal (jg/org-glossary-scan-file file)
                       (list (format "%s::*Glossary" file))))
      (delete-file file))))

(ert-deftest jg/org-glossary-quit-keeps-font-lock ()
  "A quit during `org-glossary-mode' leaves font-lock on in a visited org file."
  (let ((file (make-temp-file "glossary-quit-" nil ".org" "* Heading\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'org-glossary-mode)
                   (lambda (&rest _) (signal 'quit nil))))
          (let ((buf (condition-case nil (find-file-noselect file)
                       (quit (get-file-buffer file)))))
            (unwind-protect
                (with-current-buffer buf
                  (should font-lock-mode))
              (kill-buffer buf))))
      (delete-file file))))

(ert-deftest jg/org-table-widget-quit-keeps-font-lock ()
  "A quit during `org-table-widget-mode' leaves font-lock on in a visited org file."
  (let ((file (make-temp-file "table-widget-quit-" nil ".org"
                              "* Heading\n| a | b |\n|---+---|\n| 1 | 2 |\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'org-table-widget-mode)
                   (lambda (&rest _) (signal 'quit nil))))
          (let ((buf (condition-case nil (find-file-noselect file)
                       (quit (get-file-buffer file)))))
            (unwind-protect
                (with-current-buffer buf
                  (should font-lock-mode))
              (kill-buffer buf))))
      (delete-file file))))

(ert-deftest jg/org-table-widget-skips-large-buffers ()
  "The table widget is not scheduled for an org buffer over the size limit."
  (let ((jg/org-table-widget-max-buffer-size 10)
        (scheduled nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (&rest _) (setq scheduled t))))
      (with-temp-buffer
        (setq buffer-file-name "/tmp/large.org")
        (insert "* A heading longer than ten characters\n")
        (jg/org-table-widget-mode-maybe)
        (setq buffer-file-name nil)))
    (should-not scheduled)))
