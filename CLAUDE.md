# emacs repo

Public Emacs configuration as a literate org file. `emacs.org` is the only source; every `.el` under `emacs/` is tangled output and must not be hand-edited.

## Layout

- `emacs.org` → `emacs/init.el`, `emacs/load-first.el`, `emacs/public_config.el`, `emacs/load-last.el`, plus `emacs/essh.el`, `emacs/ob-mermaid.el`.
- The runtime `~/.emacs.d/` symlinks to these files (`init.el`, `load-first.el`, `load-last.el` at top level; `config/public_config.el`; `lisp/essh.el`, `lisp/ob-mermaid.el`). Private layers (`private_config.el`, `work.el`, `compend.el`) come from `~/repos/org/emacs/` and are not in this repo.
- Section conventions are under `** My public configuration > *** Architecture` in `emacs.org`: settings go in `*** Base Emacs` by category, `use-package` blocks go in `*** Package configuration` alphabetically.

## Tangle and reload

- Tangle only the elisp blocks (the same buffer also tangles dotfiles):
  `emacsclient --socket-name ~/.emacs.d/server/server -e '(with-current-buffer (find-file-noselect "/home/jeszyman/repos/emacs/emacs.org") (revert-buffer t t t) (org-babel-tangle nil nil "emacs-lisp"))'`
- Tangling does not change the running daemon. Eval the changed forms live, or restart.
- Stale `.elc` next to a tangled `.el` silently wins; delete it after tangling.
- Parse check for a tangled file without loading the whole config:
  `/usr/local/bin/emacs --batch --eval '(with-temp-buffer (insert-file-contents "emacs/public_config.el") (goto-char (point-min)) (while t (read (current-buffer))))'` (ends with end-of-file when clean).

## Machine facts

- On jeff-pad the shell `emacs` is `/usr/bin/emacs` 27.1. The daemon and any batch work use `/usr/local/bin/emacs` (30.1). Always give the full path in batch commands.
- Org is the 9.7.x bundled with Emacs 30. `org-src-get-lang-mode` ignores `major-mode-remap-alist`, so org source-edit buffers open in the classic modes even when files are remapped to tree-sitter modes.
- Tree-sitter grammars live in `~/.emacs.d/tree-sitter/` and self-compile at startup from the pinned sources in the `**** Tree-sitter` block. Needs `git` and `cc` on PATH.

## Gotchas found in this config

- Hooks meant for both classic and tree-sitter modes go on `python-base-mode-hook` / `sh-base-mode-hook`. `bash-ts-mode-map` does not inherit `sh-mode-map`; bind keys with `local-set-key` in the hook.
- `org-cite-biblatex-styles` entries are `(STYLE VARIANT COMMAND MULTI-COMMAND DEMOTE)`. Replacing the list with fewer fields makes every biblatex export fail with "Missing default style or variant". Extend the stock list with `add-to-list`.
- LaTeX exports run through a batch `emacs -Q` path that loads `~/repos/latex/emacs/latex_init.el`, not this config. Export-affecting settings (link abbreviations, latex classes) must also be set there.
- Helm and vertico/consult are both loaded. Consult owns `C-x b` and `C-s`; helm is kept for `helm-org` and `helm-org-rifle`.
- The `emacsclient-focus-guard` hook rejects any `--eval` string containing `switch-to-buffer`, including variable names like `switch-to-buffer-obey-display-actions`.
