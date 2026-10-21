#!/usr/bin/env bash
# Live check for the Base Emacs > Org-mode > General setting
# org-enforce-todo-checkbox-dependencies nil: a heading with an unchecked
# checkbox must still move to a done state. Runs against the running daemon in
# a temporary buffer, and also checks the tangled public_config.el.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
E=(emacsclient --socket-name "$HOME/.emacs.d/server/server")
fail=0
if grep -q "^(customize-set-variable 'org-enforce-todo-checkbox-dependencies nil)" "$here/emacs/public_config.el"; then
  echo "PASS: public_config.el sets org-enforce-todo-checkbox-dependencies to nil"
else
  echo "FAIL: public_config.el does not set org-enforce-todo-checkbox-dependencies to nil"; fail=1
fi
state=$("${E[@]}" --eval '(with-temp-buffer
  (org-mode)
  (insert "* TODO Probe heading\n- [ ] unchecked item\n")
  (goto-char (point-min))
  (let ((org-log-done nil) (org-todo-log-states nil) (inhibit-interaction t))
    (condition-case nil (org-todo "DONE") (error nil)))
  (goto-char (point-min))
  (substring-no-properties (or (org-get-todo-state) "none")))')
if [ "$state" = '"DONE"' ]; then
  echo "PASS: heading with an unchecked checkbox moved to DONE in the running Emacs"
else
  echo "FAIL: heading state after org-todo was $state"; fail=1
fi
# The setter of org-enforce-todo-checkbox-dependencies adds or removes this
# blocker function, so its presence is what actually blocks the state change.
hook=$("${E[@]}" --eval '(if (memq (quote org-block-todo-from-checkboxes) org-blocker-hook) "present" "absent")')
if [ "$hook" = '"absent"' ]; then
  echo "PASS: org-block-todo-from-checkboxes is not on org-blocker-hook"
else
  echo "FAIL: org-block-todo-from-checkboxes is on org-blocker-hook"; fail=1
fi
exit $fail
