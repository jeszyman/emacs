#!/usr/bin/env bash
# Live check for js/org-glossary-mode-maybe and js/org-table-widget-mode-maybe:
# reverting an org buffer schedules both idle timers, and when they fire they
# must enable their modes without "Error running timer: (void-variable buf)"
# (public_config.el loads without lexical-binding, so a closure over a let
# variable is void by then). Runs against the running daemon.
set -u
E=(emacsclient --socket-name "$HOME/.emacs.d/server/server")
F=$(mktemp --suffix=.org); printf '* Idle timer test\nbody\n' > "$F"
# Errors are counted by a temporary advice on `message': *Messages* folds a
# repeated line into "[N times]", so counting its lines misses repeats.
out=$("${E[@]}" --eval "(let* ((n 0)
       (probe (lambda (orig fmt &rest args)
                (when (and (stringp fmt) (string-prefix-p \"Error running timer\" fmt)
                           (string-match-p \"void-variable buf\" (format \"%S\" args)))
                  (setq n (1+ n)))
                (apply orig fmt args)))
       b)
  (advice-add 'message :around probe)
  (unwind-protect
      (progn (setq b (find-file-noselect \"$F\"))
             (with-current-buffer b (revert-buffer t t))
             (sit-for 1.5))
    (advice-remove 'message probe))
  (prog1 (format \"%s %s %s\" n
                 (if (buffer-local-value 'org-glossary-mode b) 1 0)
                 (if (buffer-local-value 'org-table-widget-mode b) 1 0))
    (kill-buffer b)))")
rm -f "$F"
read -r new gl tw <<<"$(echo "$out" | tr -d '"')"
if [ "$new" = 0 ] && [ "$gl" = 1 ] && [ "$tw" = 1 ]; then echo "PASS: both idle timers enabled their modes, no void-variable error"; exit 0; fi
echo "FAIL: new void-variable errors=$new glossary=$gl table-widget=$tw"; exit 1
