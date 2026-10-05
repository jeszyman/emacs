

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
