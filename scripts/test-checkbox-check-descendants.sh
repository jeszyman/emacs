#!/usr/bin/env bash
# Live check for Base Emacs > Org-mode > Checkbox intermediate states!:
# checking or unchecking a box with C-c C-c does the same to every box nested
# under it, and leaves boxes outside that item alone. Runs against the running
# daemon in a temporary buffer, and also checks the tangled public_config.el.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
E=(emacsclient --socket-name "$HOME/.emacs.d/server/server")
fail=0
if grep -q "^(defun my/set-descendant-checkboxes" "$here/emacs/public_config.el"; then
  echo "PASS: public_config.el defines my/set-descendant-checkboxes"
else
  echo "FAIL: public_config.el does not define my/set-descendant-checkboxes"; fail=1
fi
# Toggle the box on line LINE (1-based) of TEXT and return the buffer text.
# A third argument t runs the three-state toggle (C-u C-c C-c).
toggle() {
  "${E[@]}" --eval "(with-temp-buffer
  (org-mode)
  (insert \"$1\")
  (goto-char (point-min))
  (forward-line (1- $2))
  (my/org-toggle-checkbox-three-state ${3:-nil})
  (substring-no-properties (buffer-string)))"
}
check() {
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1"; echo "  got:      $2"; echo "  expected: $3"; fail=1; fi
}
tree='* Test\n- [ ] parent\n  - [ ] child 1\n    note under child 1\n  - [ ] child 2\n    - [ ] grandchild\n- [ ] other\n* Next\n- [ ] untouched\n'
check "checking the parent checks every nested box and nothing else" \
  "$(toggle "$tree" 2)" \
  '"* Test\n- [X] parent\n  - [X] child 1\n    note under child 1\n  - [X] child 2\n    - [X] grandchild\n- [ ] other\n* Next\n- [ ] untouched\n"'
nested='* Test\n- [ ] parent\n  - [ ] child 1\n  - [ ] child 2\n    - [ ] grandchild\n'
check "checking a child checks its grandchild only and marks the parent partial" \
  "$(toggle "$nested" 4)" \
  '"* Test\n- [-] parent\n  - [ ] child 1\n  - [X] child 2\n    - [X] grandchild\n"'
checked='* Test\n- [X] parent\n  - [X] child 1\n    note under child 1\n  - [X] child 2\n    - [X] grandchild\n- [X] other\n'
check "unchecking the parent unchecks every nested box and nothing else" \
  "$(toggle "$checked" 2)" \
  '"* Test\n- [ ] parent\n  - [ ] child 1\n    note under child 1\n  - [ ] child 2\n    - [ ] grandchild\n- [X] other\n"'
checked_nested='* Test\n- [X] parent\n  - [X] child 1\n  - [X] child 2\n    - [X] grandchild\n'
check "unchecking a child unchecks its grandchild only and marks the parent partial" \
  "$(toggle "$checked_nested" 4)" \
  '"* Test\n- [-] parent\n  - [X] child 1\n  - [ ] child 2\n    - [ ] grandchild\n"'
check "moving the parent to [-] with C-u leaves nested boxes alone" \
  "$(toggle "$nested" 2 t)" \
  '"* Test\n- [-] parent\n  - [ ] child 1\n  - [ ] child 2\n    - [ ] grandchild\n"'
exit $fail
