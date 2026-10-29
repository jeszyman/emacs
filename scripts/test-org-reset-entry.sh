#!/usr/bin/env bash
# Live check for Base Emacs > Org-mode > Checkboxes, my/org-reset-entry and
# my/org-agenda-reset-entry: a heading goes back to the first keyword of its
# TODO sequence and every checkbox in its subtree is unchecked, with no CLOSED
# line, no LOGBOOK line and no repeater shift, from the Org buffer and from an
# agenda line. Runs against the running daemon on a temporary file and its own
# agenda buffer, so the user's *Org Agenda* buffer is not touched.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
E=(emacsclient --socket-name "$HOME/.emacs.d/server/server")
fail=0
for fn in my/org-reset-entry my/org-agenda-reset-entry; do
  if grep -q "^(defun $fn " "$here/emacs/public_config.el"; then
    echo "PASS: public_config.el defines $fn"
  else
    echo "FAIL: public_config.el does not define $fn"; fail=1
  fi
done
el=$(mktemp --suffix=.el)
trap 'rm -f "$el"' EXIT
cat > "$el" <<'EOF'
(let* ((dir (make-temp-file "org-reset-test" t))
       (file (expand-file-name "reset.org" dir))
       (user-agenda (get-buffer "*Org Agenda*"))
       (user-tick (and user-agenda (buffer-modified-tick user-agenda)))
       (results nil)
       buf)
  (cl-flet ((check (name ok) (push (format "%s: %s" (if ok "PASS" "FAIL") name) results))
            (entry-text (heading)
              (with-current-buffer buf
                (save-excursion
                  (goto-char (point-min))
                  (re-search-forward (concat "^\\*+ .*" (regexp-quote heading)))
                  (org-back-to-heading t)
                  (buffer-substring-no-properties
                   (point) (save-excursion (org-end-of-subtree t t) (point)))))))
    (with-temp-file file
      (insert "* DONE Weekly review [2/2]\n"
              "CLOSED: [2026-10-28 Wed 09:00] SCHEDULED: <2026-10-29 Thu +1w>\n"
              "- [X] one\n- [X] two\n  - [X] nested\n"
              "** Child heading\n- [X] child box\n"
              "* COMPLETE Plan\n- [X] step\n"
              "* No keyword\n- [X] box\n"
              "* INPROCESS Agenda item [1/2]\n- [X] a\n- [ ] b\n"
              "* DONE Agenda done item\n- [X] c\n"))
    (setq buf (find-file-noselect file))
    (unwind-protect
        (progn
          ;; Org buffer, point on the heading line
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "Weekly review")
            (my/org-reset-entry))
          (let ((txt (entry-text "Weekly review")))
            (check "DONE goes to TODO" (string-prefix-p "* TODO Weekly review" txt))
            (check "CLOSED line removed" (not (string-match-p "CLOSED:" txt)))
            (check "repeater timestamp unchanged" (string-match-p "<2026-10-29 Thu \\+1w>" txt))
            (check "boxes in the entry and under the child heading unchecked"
                   (not (string-match-p "\\[X\\]" txt)))
            (check "heading cookie reads 0" (string-match-p "\\[0/2\\]" txt)))
          ;; Org buffer, point inside the body
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "- \\[X\\] step")
            (my/org-reset-entry))
          (let ((txt (entry-text "Plan")))
            (check "COMPLETE goes to FUTURE from a body line" (string-prefix-p "* FUTURE Plan" txt))
            (check "body box unchecked" (string-match-p "- \\[ \\] step" txt)))
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "No keyword")
            (my/org-reset-entry))
          (let ((txt (entry-text "No keyword")))
            (check "heading without keyword keeps none" (string-prefix-p "* No keyword" txt))
            (check "its box unchecked" (string-match-p "- \\[ \\] box" txt)))
          (check "no LOGBOOK or state-change line written"
                 (not (with-current-buffer buf
                        (save-excursion
                          (goto-char (point-min))
                          (re-search-forward ":LOGBOOK:\\|- State " nil t)))))
          ;; Agenda lines
          (let ((org-agenda-files (list file))
                ;; The todo and tags views take their buffer name from
                ;; `org-agenda-buffer-tmp-name' (`org-agenda--get-buffer-name').
                (org-agenda-buffer-tmp-name "*Org Agenda reset test*")
                (org-agenda-buffer-name org-agenda-buffer-name)
                (org-agenda-window-setup 'current-window)
                (org-agenda-sticky nil))
            (save-window-excursion
              (org-todo-list)
              (goto-char (point-min))
              (re-search-forward "Agenda item")
              (my/org-agenda-reset-entry)
              (check "agenda line shows TODO after reset"
                     (string-match-p "TODO Agenda item"
                                     (buffer-substring-no-properties
                                      (line-beginning-position) (line-end-position))))
              (org-tags-view nil "TODO=\"DONE\"")
              (goto-char (point-min))
              (re-search-forward "Agenda done item")
              (my/org-agenda-reset-entry)
              (when (get-buffer "*Org Agenda reset test*")
                (kill-buffer "*Org Agenda reset test*"))))
          (let ((txt (entry-text "Agenda item [")))
            (check "agenda reset: INPROCESS goes to TODO in the file" (string-prefix-p "* TODO Agenda item" txt))
            (check "agenda reset: boxes unchecked in the file" (not (string-match-p "\\[X\\]" txt))))
          (let ((txt (entry-text "Agenda done item")))
            (check "agenda reset: DONE goes to TODO in the file" (string-prefix-p "* TODO Agenda done item" txt))
            (check "agenda reset: box unchecked in the file" (string-match-p "- \\[ \\] c" txt)))
          (check "user's *Org Agenda* buffer unchanged"
                 (or (not user-agenda)
                     (and (buffer-live-p user-agenda)
                          (= user-tick (buffer-modified-tick user-agenda))))))
      (with-current-buffer buf (set-buffer-modified-p nil))
      (kill-buffer buf)
      (delete-directory dir t)))
  (mapconcat #'identity (nreverse results) "\n"))
EOF
out=$("${E[@]}" --eval "(condition-case err (with-temp-buffer (insert-file-contents \"$el\") (eval (read (current-buffer)) t)) (error (format \"FAIL: error %S\" err)))")
# emacsclient prints the string with quotes and \n escapes
printf '%b\n' "$(echo "$out" | sed 's/^"//; s/"$//')"
echo "$out" | grep -q "FAIL" && fail=1
exit $fail
