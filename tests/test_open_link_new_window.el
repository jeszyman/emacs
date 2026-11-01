;; Regression test for C-u C-c C-o in org buffers (`my-org-open-at-point') and
;; the agenda (`my-org-agenda-open-link').
;; Run against the live daemon, which has the config loaded:
;;   emacsclient --socket-name ~/.emacs.d/server/server --eval \
;;     '(let (r) (with-temp-buffer (insert-file-contents "~/repos/emacs/tests/test_open_link_new_window.el") (condition-case nil (while t (push (eval (read (current-buffer)) t) r)) (end-of-file))) (nreverse r))'
;; Returns one result per top-level form, each (PASS ...) or (FAIL ...). In the
;; first form each case must open exactly one new frame visiting the test's
;; target.org; the frames and buffers it creates are removed.
(let* ((dir (make-temp-file "open-link-test" t))
       (target (expand-file-name "target.org" dir))
       (other (expand-file-name "other.org" dir))
       (src (expand-file-name "src.org" dir))
       (id "0b1f6d2e-open-link-test-target")
       ;; A copy, so the test ID never reaches the saved ID locations.
       (org-id-locations (let ((h (copy-hash-table org-id-locations)))
                           (puthash id target h)
                           h))
       (run
        (lambda (name move cmd)
          (let ((before (frame-list)) new)
            (save-window-excursion
              (with-current-buffer (find-file-noselect src)
                (goto-char (point-min))
                (funcall move)
                ;; Stub the link picker's keypress: choose link 1.
                (cl-letf (((symbol-function 'read-char-exclusive) (lambda (&rest _) ?1)))
                  (funcall cmd))))
            (setq new (cl-set-difference (frame-list) before))
            (let ((file (and new (buffer-file-name (window-buffer (frame-selected-window (car new)))))))
              (mapc #'delete-frame new)
              (list (if (and (= (length new) 1) (equal file target)) 'PASS 'FAIL)
                    name :new-frames (length new) :file file)))))
       (org-cmd (lambda () (my-org-open-at-point '(4))))
       ;; An agenda line: a buffer in org-agenda-mode whose line carries the
       ;; entry marker, as the agenda builds it.
       (agenda-cmd
        (lambda ()
          (let ((m (point-marker)))
            (with-temp-buffer
              (org-agenda-mode)
              (insert (propertize "  TODO Head" 'org-hd-marker m 'org-marker m))
              (my-org-agenda-open-link '(4)))))))
  (with-temp-file target (insert "* Target\n:PROPERTIES:\n:ID: " id "\n:END:\nbody\n"))
  (with-temp-file other (insert "* Other\n"))
  (with-temp-file src
    (insert "* Head [[file:target.org][one]] and [[file:other.org][two]]\n"
            "* Id head\n- [[id:" id "][target by id]]\n- [[file:other.org][two]]\n"))
  (unwind-protect
      (mapcar (lambda (c) (condition-case e (apply run c) (error (list 'ERROR (car c) e))))
              (list (list "from-heading" #'ignore org-cmd)
                    (list "on-link" (lambda () (search-forward "[[file:target")) org-cmd)
                    (list "agenda-line" #'ignore agenda-cmd)
                    (list "agenda-line-id" (lambda () (re-search-forward "^\\* Id head")
                                             (beginning-of-line))
                          agenda-cmd)))
    (dolist (f (list src target other))
      (let ((b (get-file-buffer f))) (when b (kill-buffer b))))
    (delete-directory dir t)))
;; A URL in a property drawer is a node property to Org, not a link; C-u C-c
;; C-o must still start "brave-browser --new-window URL". The browser launch
;; is stubbed and its arguments checked.
(let (log
      (url "https://example.com/property-url"))
  (with-temp-buffer
    (insert "* Recipe\n:PROPERTIES:\n:SOURCE_URL: " url "\n:END:\n")
    (org-mode)
    (goto-char (point-min))
    (search-forward "https://example")
    (cl-letf (((symbol-function 'start-process) (lambda (&rest a) (push a log) nil))
              ((symbol-function 'browse-url) (lambda (&rest a) (push (cons 'browse-url a) log) nil)))
      (let ((current-prefix-arg '(4)))
        (call-interactively (key-binding (kbd "C-c C-o"))))))
  (list (if (equal log (list (list "brave-new-window" nil "brave-browser" "--new-window" url)))
            'PASS 'FAIL)
        "property-url" :calls log))
