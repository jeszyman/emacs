;;; org-at-id-nosteal-test.el --- jg/org-at-id-nosteal writes state-change notes at once  -*- lexical-binding: t; -*-
;; Run: /usr/local/bin/emacs -Q --batch -l tests/org-at-id-nosteal-test.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'org)
(require 'org-id)

(defconst nosteal-test--config
  (expand-file-name "../emacs/public_config.el" (file-name-directory (or load-file-name buffer-file-name))))

;; Load only the helper's defun from the tangled config.
(with-temp-buffer
  (insert-file-contents nosteal-test--config)
  (goto-char (point-min))
  (search-forward "(defun jg/org-at-id-nosteal")
  (goto-char (match-beginning 0))
  (eval (read (current-buffer)) t))

(ert-deftest nosteal-writes-state-change-note ()
  "A logged state change made through the helper lands in the LOGBOOK before it returns."
  (let* ((file (make-temp-file "nosteal" nil ".org"))
         (id "aaaa1111-2222-3333-4444-nosteal0test")
         (org-todo-keywords '((sequence "TODO(t)" "INPROCESS(p!)" "|" "DONE(d)")))
         (org-log-into-drawer t)
         ;; Mirror an interactive session, where some mode makes the hook buffer-local.
         (org-mode-hook (list (lambda () (add-hook 'post-command-hook #'ignore nil t)))))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO Test heading\n:PROPERTIES:\n:ID:       " id "\n:END:\n"))
          (with-current-buffer (find-file-noselect file)
            (org-mode)
            (org-id-add-location id file))
          (jg/org-at-id-nosteal id (lambda () (org-todo "INPROCESS")))
          (should (string-match-p "State \"INPROCESS\"  from \"TODO\""
                                  (with-temp-buffer (insert-file-contents file) (buffer-string)))))
      (remove-hook 'post-command-hook #'org-add-log-note)
      (let ((b (find-buffer-visiting file))) (when b (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b)))
      (delete-file file))))
