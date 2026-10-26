

;; Regression test, run in the live daemon: opening an org buffer that contains an =#+INCLUDE= line leaves ~org-include-inline-mode~ off.

;; #+name: org-include-inline-test

;;; org-include-inline-test.el --- live-daemon ERT test  -*- lexical-binding: t; -*-
;; Run: emacsclient --socket-name ~/.emacs.d/server/server --eval
;;   '(progn (load-file "~/repos/emacs/tests/org-include-inline-test.el")
;;           (ert-stats-completed-unexpected (ert-run-tests-batch "js/org-include-inline")))'
;; A result of 0 means pass.
(require 'ert)

(ert-deftest js/org-include-inline-not-auto-enabled ()
  "An org buffer with an #+INCLUDE line does not turn on `org-include-inline-mode'."
  (with-temp-buffer
    (insert "* Heading\n#+INCLUDE: \"other.org::#custom-id\" :only-contents t\n")
    (org-mode)
    (should-not (bound-and-true-p org-include-inline-mode))))
