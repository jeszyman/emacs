#!/usr/bin/env bash
# Regression test for the block server-eval-noprompt: an emacsclient --eval that
# meets a file-changed-on-disk question must answer at once instead of blocking
# the Emacs server. Each case runs in a private scratch daemon (socket
# emacs-noprompt-test, one hidden X frame; the running Emacs is never touched),
# first without the block, where every case must block (proof the test reaches
# the questions), then with it, where none may. Needs DISPLAY. Exit 0 = pass.
set -u
ORG="${1:-$HOME/repos/emacs/emacs.org}"
SOCK=emacs-noprompt-test
FIX=$(mktemp --suffix=.el)
trap 'rm -f "$FIX"' EXIT
emacs -Q --batch --eval "(progn (require 'org) (with-temp-buffer (insert-file-contents \"$ORG\") (org-mode) (org-babel-goto-named-src-block \"server-eval-noprompt\") (write-region (org-element-property :value (org-element-at-point)) nil \"$FIX\")))" 2>/dev/null
[ -s "$FIX" ] || { echo "FAIL: block server-eval-noprompt not found in $ORG"; exit 1; }

ec() { timeout "$1" emacsclient -s "$SOCK" --eval "$2" 2>&1; echo "exit=$?"; }
stop() { timeout 2 emacsclient -s "$SOCK" --eval '(kill-emacs)' >/dev/null 2>&1; pkill -f "[d]aemon=emacs-noprompt-test"; sleep 0.5; }
start() {
  emacs -Q --daemon="$SOCK" >/dev/null 2>&1
  ec 5 '(select-frame (make-frame-on-display (getenv "DISPLAY") (quote ((visibility . nil)))))' >/dev/null
  if [ -n "$1" ]; then ec 5 "(load \"$1\" nil t)" >/dev/null; fi
}

# Modified buffer, file changed on disk, then save-buffer.
case1() { local f; f=$(mktemp --suffix=.org); printf '* a\n' >"$f"
  ec 3 "(with-current-buffer (find-file-noselect \"$f\") (goto-char (point-max)) (insert \"buffer edit\") nil)" >/dev/null
  sleep 1.1; printf '* a\n* disk edit\n' >"$f"
  ec 4 "(with-current-buffer (get-file-buffer \"$f\") (save-buffer) nil)"; rm -f "$f"; }
# Unmodified buffer, file changed on disk, then find-file-noselect.
case2() { local f; f=$(mktemp --suffix=.org); printf '* b\n' >"$f"
  ec 3 "(progn (find-file-noselect \"$f\") nil)" >/dev/null
  sleep 1.1; printf '* b\n* disk edit 2\n' >"$f"
  ec 4 "(with-current-buffer (find-file-noselect \"$f\") (buffer-substring-no-properties (point-min) (point-max)))"; rm -f "$f"; }
# Unmodified buffer, file changed on disk, then an eval inserts text.
case3() { local f; f=$(mktemp --suffix=.org); printf '* c\n' >"$f"
  ec 3 "(progn (find-file-noselect \"$f\") nil)" >/dev/null
  sleep 1.1; printf '* c\n* disk edit 3\n' >"$f"
  ec 4 "(with-current-buffer (get-file-buffer \"$f\") (goto-char (point-max)) (insert \"x\") nil)"; rm -f "$f"; }

fail=0
check() {  # name, output, grep pattern that must match
  if printf '%s' "$2" | grep -q -- "$3"; then echo "pass: $1"; else echo "FAIL: $1"; printf '%s\n' "$2" | sed 's/^/    /'; fail=1; fi
}
for c in case1 case2 case3; do
  stop; start ""; check "$c blocks without the fix" "$($c)" "exit=124"
  stop; start "$FIX"; out=$($c)
  case $c in
    case1) check "$c returns an error with the fix" "$out" "refused to ask: .*Save anyway" ;;
    case2) check "$c rereads the file with the fix" "$out" "disk edit 2" ;;
    case3) check "$c returns an error with the fix" "$out" "did not edit the buffer" ;;
  esac
  check "$c server still answers after" "$(ec 3 '(+ 1 1)')" "^2$"
done
stop
exit $fail
