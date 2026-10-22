#!/usr/bin/env bash
# Live check for js/server-send-string-ignore-dead-client in the block
# server-eval-noprompt: an emacsclient killed by its timeout while the daemon is
# busy must not add "no longer connected to pipe; closed it" to *Messages*.
# Runs against the running daemon; the kill happens before the busy loop ends,
# so the daemon writes its reply to a closed socket.
set -u
E=(emacsclient --socket-name "$HOME/.emacs.d/server/server")
count() { "${E[@]}" --eval '(with-current-buffer "*Messages*" (count-matches "no longer connected to pipe" (point-min) (point-max)))'; }
before=$(count)
timeout 0.3 "${E[@]}" --eval '(let ((t0 (float-time))) (while (< (- (float-time) t0) 1.5)) "busy")' >/dev/null 2>&1
sleep 2.5
after=$(count)
if [ "$before" = "$after" ]; then echo "PASS: dead-client reply dropped ($before pipe-closed messages before and after)"; exit 0; fi
echo "FAIL: pipe-closed messages went from $before to $after"; exit 1
