;;; repeat-skip-test.el --- :REPEAT_CRON: dates that skip a list of days  -*- lexical-binding: t; -*-
;; Run: /usr/local/bin/emacs --batch -Q -l ert -l tests/repeat-skip-test.el -f ert-run-tests-batch-and-exit
;; 2026-11-24: an aftercare pickup stood on Wed 11-25 and a drop-off on Thanksgiving.
(require 'package)
(package-initialize)
(require 'org)
(require 'org-repeat-by-cron)

(defconst repeat-skip-test--config
  (expand-file-name "../emacs/public_config.el"
                    (file-name-directory (or load-file-name buffer-file-name))))

;; Evaluate only the js/repeat-skip forms; the rest of the config is not loaded in batch.
(with-temp-buffer
  (insert-file-contents repeat-skip-test--config)
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (and (consp form)
                     (memq (car form) '(defun defvar defconst))
                     (string-prefix-p "js/repeat-skip" (symbol-name (cadr form))))
            (eval form t))))
    (end-of-file nil)))

(when (fboundp 'js/repeat-skip--next-time)
  (advice-add 'org-repeat-by-cron-next-time :around #'js/repeat-skip--next-time))
(global-org-repeat-by-cron-mode)

(defmacro repeat-skip-test--with (sched rule prop &rest body)
  "Run BODY on an entry scheduled SCHED with RULE and drawer line PROP."
  (declare (indent 3))
  `(let* ((dir (make-temp-file "skip" t))
          (js/repeat-skip-dir dir)
          (file (expand-file-name "a.org" dir))
          (org-todo-keywords '((sequence "TODO" "|" "DONE")))
          (org-log-done nil) (org-log-repeat nil) (org-inhibit-logging t))
     (with-temp-file (expand-file-name "school" dir)
       (insert "2031-01-08\n2031-01-09\n2031-01-10\n"))
     (with-temp-file file
       (insert "* TODO Pick up\nSCHEDULED: <" ,sched ">\n:PROPERTIES:\n:REPEAT_CRON: " ,rule
               "\n:REPEAT_ANCHOR: " ,sched "\n" ,prop ":END:\n"))
     (with-current-buffer (find-file-noselect file)
       (unwind-protect (progn (goto-char (point-min)) ,@body)
         (set-buffer-modified-p nil)
         (kill-buffer)
         (delete-directory dir t)))))

(defun repeat-skip-test--dates ()
  (goto-char (point-min))
  (list (org-entry-get nil "SCHEDULED") (org-entry-get nil "REPEAT_ANCHOR")))

(defconst repeat-skip-test--on ":REPEAT_SKIP: school\n")

(ert-deftest repeat-skip-done-passes-over-listed-days ()
  (repeat-skip-test--with "2031-01-03 Fri 16:30" "* * 3,5" repeat-skip-test--on
    (org-todo "DONE")
    (should (equal (repeat-skip-test--dates)
                   '("<2031-01-15 Wed 16:30>" "2031-01-15 Wed 16:30")))))

(ert-deftest repeat-skip-done-five-field-rule ()
  (repeat-skip-test--with "2031-01-07 Tue 08:20" "20 08 * * 2,4" repeat-skip-test--on
    (org-todo "DONE")
    (should (equal (car (repeat-skip-test--dates)) "<2031-01-14 Tue 08:20>"))))

(ert-deftest repeat-skip-unmarked-entry-unchanged ()
  (repeat-skip-test--with "2031-01-03 Fri 16:30" "* * 3,5" ""
    (org-todo "DONE")
    (should (equal (car (repeat-skip-test--dates)) "<2031-01-08 Wed 16:30>"))))

(ert-deftest repeat-skip-missing-list-uses-the-rule ()
  (repeat-skip-test--with "2031-01-03 Fri 16:30" "* * 3,5" ":REPEAT_SKIP: nolist\n"
    (org-todo "DONE")
    (should (equal (car (repeat-skip-test--dates)) "<2031-01-08 Wed 16:30>"))))

(ert-deftest repeat-skip-fix-moves-an-entry-off-a-listed-day ()
  (repeat-skip-test--with "2031-01-08 Wed 16:30-17:00" "* * 3,5" repeat-skip-test--on
    (should (= 1 (js/repeat-skip-fix (list file))))
    (should (equal (repeat-skip-test--dates)
                   '("<2031-01-15 Wed 16:30-17:00>" "2031-01-15 Wed 16:30-17:00")))
    (should-not (buffer-modified-p))
    (should (= 0 (js/repeat-skip-fix (list file))))))

(ert-deftest repeat-skip-fix-leaves-a-school-day ()
  (repeat-skip-test--with "2031-01-15 Wed 16:30" "* * 3,5" repeat-skip-test--on
    (should (= 0 (js/repeat-skip-fix (list file))))))

(ert-deftest repeat-skip-fix-leaves-an-unsaved-buffer ()
  (repeat-skip-test--with "2031-01-08 Wed 16:30" "* * 3,5" repeat-skip-test--on
    (goto-char (point-max)) (insert "x")
    (should (= 0 (js/repeat-skip-fix (list file))))
    (should (equal (car (repeat-skip-test--dates)) "<2031-01-08 Wed 16:30>"))))
