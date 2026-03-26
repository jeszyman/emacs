;; Base Emacs
;; - Frozen Emacs: =pkill -USR2 emacs=

(remove-hook 'before-save-hook #'org-table-recalculate-buffer-tables)
(advice-add 'revert-buffer :around
  (lambda (orig &rest args)
  (advice-mapc (lambda (f props) (message "%s %s" (car props) f)) 'revert-buffer)
    (if (derived-mode-p 'org-mode)
        (org-fold-save-outline-visibility t
          (apply orig args))
      (apply orig args)))
  '((name . org/preserve-outline-visibility)))
;; Dired
;; - whenever you open a new directory in Dired, the old Dired buffer is automatically killed

(setq dired-kill-when-opening-new-dired-buffer t)
(setq dired-dwim-target t)

;; - when listing files:

(setq dired-listing-switches "-alh")

;;   -a → show all files, including dotfiles (. and ..).
;;   - -l → use long listing format (permissions, owner, size, modification time).
;;   -h → show file sizes in “human-readable” units (e.g. 1K, 2M, 3G).
;; - Open files using [[id:05e700d9-77cc-4aef-b310-164c267274d0][xdg-utils]]

    (defun my/dired-open-xdg ()
      "Open file at point with xdg-open."
      (interactive)
      (let ((file (dired-get-file-for-visit)))
	(start-process "xdg-open" nil "xdg-open" file)))

    ;; Bind to a key in dired-mode
    (with-eval-after-load 'dired
      (define-key dired-mode-map (kbd "E") #'my/dired-open-xdg))
;; Needed in --batch
;; Code that needs to be tangled both here and into custom inits for batch export
;; #+name need_in_batch

(setq large-file-warning-threshold most-positive-fixnum) ; disable large file warning
(setq-default cache-long-scans nil)
;; Comint

(setq comint-scroll-to-bottom-on-output t
      comint-move-point-for-output t)
;; Appearance

; ---   General   --- ;
; ------------------- ;

(setq frame-background-mode 'dark)
(setq inhibit-splash-screen t)
(setq redisplay-skip-fontification-on-input t)

; ---   Windows   --- ;
; ------------------- ;

;; Remove bars:
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode 'right) ;; Place scroll bar on the right side
(scroll-bar-mode -1)

;
; Fringe- Set finge color to background
;https://emacs.stackexchange.com/a/31944/11502
(set-face-attribute 'fringe nil :background 'unspecified)

; ---   Lines   --- ;
; ----------------- ;

;;
;; Enable visual line mode
(global-visual-line-mode 1)
;;
;; Line highlighting in all buffers
(global-hl-line-mode t)
;;
;; Line numbers
(global-display-line-numbers-mode 0)
;;;
;;; Disable line numbers by buffer
(dolist (mode '(org-mode-hook
                term-mode-hook
                shell-mode-hook
                eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))
;;
(setq-default indicate-empty-lines t)

; Do not wrap lines, but extend them off screen
(setq default-truncate-lines nil)

;; no line numbers
(setq global-linum-mode nil)

; ---   Syntax Highlighting   --- ;
; ------------------------------- ;

;; When enabled, any matching parenthesis is highlighted
(show-paren-mode)
;;
;; Enables highlighting of the region whenever the mark is active
(transient-mark-mode 1)

; ---   Code   --- ;
; ---------------- ;

;; Delimiters
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

; ---   Faces   --- ;
; ----------------- ;

;; ?Fix broken face inheritance
(let ((faces (face-list)))
  (dolist (face faces)
    (let ((inh (face-attribute face :inherit)))
      (when (not (memq inh faces))
        (set-face-attribute face nil :inherit nil)))))

; ---   Text   --- ;
; ---------------- ;

;https://emacs.stackexchange.com/questions/72483/how-to-define-consult-faces-generically-for-minibuffer-highlighting-that-fits-wi
(global-hl-line-mode 1)
(set-face-attribute 'highlight nil :background "#294F6E")
;; Tramp

(setq tramp-default-method "ssh")

(defadvice tramp-completion-handle-file-name-all-completions
  (around dotemacs-completion-docker activate)
  "(tramp-completion-handle-file-name-all-completions \"\" \"/docker:\" returns
    a list of active Docker container names, followed by colons."
  (if (equal (ad-get-arg 1) "/docker:")
      (let* ((dockernames-raw (shell-command-to-string "docker ps | awk '$NF != \"NAMES\" { print $NF \":\" }'"))
             (dockernames (cl-remove-if-not
                           #'(lambda (dockerline) (string-match ":$" dockerline))
                           (split-string dockernames-raw "\n"))))
        (setq ad-return-value dockernames))
    ad-do-it))

; https://emacs.stackexchange.com/questions/29286/tramp-unable-to-open-some-files
(setq tramp-copy-size-limit 10000000)
;; Key bindings

; ASCII Arrows

; ---   ASCII Arrows   --- ;
; ------------------------ ;

(global-set-key (kbd "C-<right>") (lambda () (interactive) (insert "\u2192")))
(global-set-key (kbd "C-<up>") (lambda () (interactive) (insert "\u2191")))

; ---   Disable Keys   --- ;
; ------------------------ ;

;; Minimize
(global-unset-key (kbd "C-z"))
;; Print
(global-unset-key (kbd "s-p"))

(global-set-key (kbd "C-S-n")
		(lambda () (interactive) (next-line 10)))
(global-set-key (kbd "C-S-p")
		(lambda () (interactive) (next-line -10)))
;; On-save hooks and backup
;; Three backup mechanisms are active, each covering a different failure mode:

;; | Mechanism      | Location                       | Trigger                        | Naming                           | Recovery use                                |
;; |----------------+--------------------------------+--------------------------------+----------------------------------+---------------------------------------------|
;; | Backup files   | =~/.emacs.d/backup-save-list/= | Each =save-buffer=             | =!path!to!file~= (up to 20 kept) | Recover from bad saves or destructive edits |
;; | Auto-save      | =~/.emacs.d/auto-save-list/=   | Periodic (idle timer / crash)  | =#!path!to!file#=                | Recover from crashes or unsaved work        |
;; | Version backup | =~/.emacs.d/backup-save-list/= | First save of VC-tracked files | =!path!to!file.~N~= (numbered)   | Recover older revisions                     |

;; - *Backup files* (`backup-directory-alist`): on every save, Emacs copies the previous version to =~/.emacs.d/backup-save-list/= with =!=-delimited path encoding. Keeps 20 old versions (`delete-old-versions`). Also covers VC-tracked files (`vc-make-backup-files t`).
;; - *Auto-save files* (`auto-save-file-name-transforms`): Emacs periodically writes unsaved buffer state to =~/.emacs.d/auto-save-list/= using =#=-delimited naming. These are deleted on normal save but survive crashes. Recover with =M-x recover-file=.
;; - *Stale dirs*: =~/repos/org/auto-save-list/= and =~/repos/org/backups/= exist from an older config but are no longer written to. All active backups go to =~/.emacs.d/=.

;; Shorthand for save all buffers
;;  https://stackoverflow.com/questions/15254414/how-to-silently-save-all-buffers-in-emacs
(defun save-all ()
  (interactive)
  (save-some-buffers t))

; ---   Saving And Backup   --- ;
; ----------------------------- ;

; Delete trailing whitespace on save
(add-hook 'before-save-hook
          'delete-trailing-whitespace)

;; Backup process upon save
(setq backup-by-copying t)         ; Copy, don't rename — preserves the original inode
(setq version-control t)           ; Use numbered backups (file.~1~, file.~2~, etc.)
(setq kept-new-versions 20)        ; Keep 20 newest numbered backups
(setq kept-old-versions 5)         ; Keep 5 oldest numbered backups
(setq delete-old-versions t)       ; Auto-delete excess backups without prompting
(setq vc-make-backup-files t)      ; Also back up version-controlled files
(setq backup-directory-alist '(("." . "~/.emacs.d/backup-save-list")))

(setq auto-save-visited-mode t) ; Visited files will be auto-saved

(setq auto-save-file-name-transforms
      `((".*" ,(concat user-emacs-directory "auto-save-list/") t)))
;; Miscellaneous

; ---   Miscellaneous   --- ;
; ------------------------- ;

;https://emacs.stackexchange.com/questions/62419/what-is-causing-emacs-remote-shell-to-be-slow-on-completion
(defun my-shell-mode-setup-function ()
  (when (and (fboundp 'company-mode)
             (file-remote-p default-directory))
    (company-mode -1)))

(add-hook 'shell-mode-hook 'my-shell-mode-setup-function)

;; delete the region when typing, just like as we expect nowadays.
(delete-selection-mode t)

(setq explicit-shell-file-name "/bin/bash")

;; Don't count two spaces after a period as the end of a sentence.
(setq sentence-end-double-space nil)

;; don't check package signatures
;;  https://emacs.stackexchange.com/questions/233/how-to-proceed-on-package-el-signature-check-failure
(setq package-check-signature nil)

;; Avoid nesting exceeds max-lisp-eval-depth error
;;  https://stackoverflow.com/questions/11807128/emacs-nesting-exceeds-max-lisp-eval-depth
(setq max-lisp-eval-depth 1200)

;; allow remembering risky variables
;;  https://emacs.stackexchange.com/questions/10983/remember-permission-to-execute-risky-local-variables
(defun risky-local-variable-p (sym &optional _ignored) nil)

; Disable "buffer is read only" warning
;;https://emacs.stackexchange.com/questions/19742/is-there-a-way-to-disable-the-buffer-is-read-only-warning
(defun my-command-error-function (data context caller)
  "Ignore the buffer-read-only signal; pass the rest to the default handler."
  (when (not (eq (car data) 'buffer-read-only))
    (command-error-default-function data context caller)))

(setq command-error-function #'my-command-error-function)

; Follow symlinks in dired
;;https://emacs.stackexchange.com/questions/41286/follow-symlinked-directories-in-dired
(setq find-file-visit-truename t)
(setq vc-follow-symlinks t)

(setq browse-url-browser-function 'browse-url-generic
      browse-url-generic-program "/usr/bin/brave-browser")

; y or n instead of yes or no
(setopt use-short-answers t)

;; Minibuffer prompts follow the selected frame, so any frame can answer
;; a blocking y/n prompt instead of hunting for the originating frame
(setq minibuffer-follows-selected-frame t)

;; Don't prompt about active processes on exit
(setq confirm-kill-processes nil)

;; don't check package signatures
;;  https://emacs.stackexchange.com/questions/233/how-to-proceed-on-package-el-signature-check-failure
(setq package-check-signature nil)

;; Avoid nesting exceeds max-lisp-eval-depth error
;;  https://stackoverflow.com/questions/11807128/emacs-nesting-exceeds-max-lisp-eval-depth
(setq max-lisp-eval-depth 1200)
;;

;; normal c-c in ansi-term
;; https://emacs.stackexchange.com/questions/32491/normal-c-c-in-ansi-term
(eval-after-load "term"
  '(progn (term-set-escape-char ?\C-c)
          (define-key term-raw-map (kbd "C-c") nil)))

(setq comint-scroll-to-bottom-on-output t)

;; allow kill hidden part of line
;;  https://stackoverflow.com/questions/3281581/how-to-word-wrap-in-emacs
(setq-default word-wrap t)

;; auto-refresh if source changes
;;  https://stackoverflow.com/questions/1480572/how-to-have-emacs-auto-refresh-all-buffers-when-files-have-changed-on-disk
(global-auto-revert-mode 1)

; ---   Frames And Windows   --- ;
; ------------------------------ ;

(setq truncate-partial-width-windows nil)
(setq split-window-preferred-function (quote split-window-sensibly))

; ---   Other   --- ;
; ----------------- ;

(setq require-final-newline nil)
(defun toggle-theme ()
  "Toggle between dark and light themes."
  (interactive)
  (if (custom-theme-enabled-p 'manoj-dark)
      (progn
        (disable-theme 'manoj-dark)
        (load-theme 'leuven t))
    (progn
      (disable-theme 'leuven)
      (load-theme 'manoj-dark t))))
(setq create-lockfiles nil)
;; (open-texdoc-in-background)

(defun open-texdoc-in-background (docname)
  "Open a TEXDOC for DOCNAME in the background and close the terminal."
  (interactive "sEnter the name of the document: ")
  (let ((term-buffer (ansi-term "/bin/bash")))
    (with-current-buffer term-buffer
      (term-send-raw-string (concat "texdoc " docname "\n"))
      (term-send-raw-string "sleep 2; exit\n")
      (set-process-sentinel
       (get-buffer-process term-buffer)
       (lambda (process signal)
         (when (or (string= signal "finished\n")
                   (string= signal "exited\n"))
           (kill-buffer (process-buffer process)))))
      (bury-buffer))))
;; PDF annotation
;; Extract highlights and comments from a PDF into a temporary org buffer.
;; When point is on an org-cite reference, resolves the PDF automatically via =citar=.
;; Requires =pdfannots= on PATH (=pip install pdfannots=).

(defun my/pdf-from-cite-at-point ()
  "Return the PDF path for the org-cite key at point, or nil if not on a citation.
citar-get-files returns a hash-table keyed by citekey; extract the list with gethash."
  (when-let* ((elem (org-element-context))
              (_ (eq (org-element-type elem) 'citation-reference))
              (key (org-element-property :key elem))
              (files-hash (let ((inhibit-message t) (message-log-max nil))
                            (citar-get-files (list key))))
              (files (gethash key files-hash))
              (pdf (seq-find (lambda (f) (string-match-p "\\.pdf\\'" f)) files)))
    pdf))
(defun my/extract-pdf-annotations (pdf-file)
  "Extract highlights and comments from PDF-FILE into a temporary org buffer.
When point is on an org-cite reference, resolves the PDF automatically via citar.
Requires pdfannots to be installed and on PATH."
  (interactive
   (list (or (my/pdf-from-cite-at-point)
             (read-file-name "PDF file: " nil nil t nil
                             (lambda (f) (string-match-p "\\.pdf\\'" f))))))
  (let* ((output (shell-command-to-string
                  (concat "pdfannots " (shell-quote-argument (expand-file-name pdf-file)))))
         (buf (get-buffer-create "*pdf-annotations*")))
    (with-current-buffer buf
      (erase-buffer)
      (org-mode)
      (insert (format "#+title: Annotations: %s\n\n" (file-name-nondirectory pdf-file)))
      (insert output))
    (switch-to-buffer buf)))
;; Make header regions read-only via tag

(defun org-mark-readonly ()
  (interactive)
  (let ((buf-mod (buffer-modified-p)))
    (org-map-entries
     (lambda ()
       (org-mark-subtree)
       (add-text-properties (region-beginning) (region-end) '(read-only t)))
     "read_only")
    (unless buf-mod
      (set-buffer-modified-p nil))))

(defun org-remove-readonly ()
  (interactive)
  (let ((buf-mod (buffer-modified-p)))
    (org-map-entries
     (lambda ()
       (let* ((inhibit-read-only t))
     (org-mark-subtree)
     (remove-text-properties (region-beginning) (region-end) '(read-only t))))
     "read_only")
    (unless buf-mod
      (set-buffer-modified-p nil))))

(add-hook 'org-mode-hook 'org-mark-readonly)
;; Protect text regions as read-only
;; https://chatgpt.com/c/fe962d8c-eb34-42fe-b362-032a61d8b728

(defun make-region-read-only (start end)
  (interactive "*r")
  (let ((inhibit-read-only t))
    (put-text-property start end 'read-only t)
    (put-text-property start end 'font-lock-face '(:background "#8B0000"))))

(defun make-region-read-write (start end)
  (interactive "*r")
  (let ((inhibit-read-only t))
    (put-text-property start end 'read-only nil)
    (remove-text-properties start end '(font-lock-face nil))))
;; Shell

(defun dont-ask-to-kill-shell-buffer ()
  "Don't ask for confirmation when killing *shell* buffer."
  (let ((buffer-name (buffer-name)))
    (when (string-equal buffer-name "*shell*")
      (setq kill-buffer-query-functions
            (delq 'process-kill-buffer-query-function
                  kill-buffer-query-functions)))))

(add-hook 'shell-mode-hook 'dont-ask-to-kill-shell-buffer)
;; cua-mode

(cua-mode t)
(defun jg/cua-paste-clean (orig-fun &rest args)
  "When called with C-u prefix, paste with line breaks replaced by spaces."
  (if current-prefix-arg
      (let ((clipboard-content (current-kill 0)))
        (insert (replace-regexp-in-string "\n" " " clipboard-content)))
    (apply orig-fun args)))

(advice-add 'cua-paste :around #'jg/cua-paste-clean)
;; Emacs caches the X clipboard selection (gui--last-selected-text-clipboard)
;; and returns stale text when an external app overwrites CLIPBOARD after
;; Emacs last set it.  Fix: clear the cache before every paste so
;; gui-get-selection always re-queries X via native protocol.
;; Using gui-get-selection instead of shelling out to xclip avoids
;; subprocess hangs in some frames.
(setq interprogram-paste-function
      (lambda ()
        (setq gui--last-selected-text-clipboard nil)
        (condition-case nil
            (let ((text (gui-get-selection 'CLIPBOARD 'UTF8_STRING)))
              (when (and (stringp text) (> (length text) 0)
                         (not (string= text (or (car kill-ring) ""))))
                (substring-no-properties text)))
          (error nil))))
;; remove-blank-lines

(defun remove-blank-lines ()
  "Remove all blank lines (including lines with only whitespace) in the current buffer."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (flush-lines "^[[:space:]]*$")))
;; Window navigation

;; Focus on another split in one step: switch to next window, then make it the
;; only visible window. Replaces the two-step C-x o then C-x 1 sequence.
(defun my/other-window-only ()
  "Switch to the next window and delete all others."
  (interactive)
  (other-window 1)
  (delete-other-windows))

;; C-x O (capital O) — distinct from the built-in C-x o (other-window)
(global-set-key (kbd "C-x O") #'my/other-window-only)
;; key-chord "oo" for fast single-handed access
(key-chord-define-global "OO" #'my/other-window-only)
;; Startup

(require 'org)
(setq org-startup-folded t)
(setq org-startup-with-inline-images t)
;; Add persistant highlights

(defun org-add-persistent-highlights ()
  "Add persistent highlighting for custom markers in Org mode."
  (font-lock-add-keywords
   nil
   '(("<{\\(.*?\\)}>" ; Match the pattern <{...}>
      (1 '(:background "firebrick") t)))))

(add-hook 'org-mode-hook #'org-add-persistent-highlights)

(defun org-hide-markers-without-space ()
  "Hide markers like << and >> in Org-mode without leaving empty space."
  (font-lock-add-keywords
   nil
   '(("<{\\|}>"
      (0 (progn (put-text-property (match-beginning 0) (match-end 0)
                                   'display "")
                'org-hide))))))

(add-hook 'org-mode-hook #'org-hide-markers-without-space)
;; Tags

        (setq
         org-tags-exclude-from-inheritance
         (list
	  "alert"
          "biotool"
          "biopipe"
          "bimonthly"
          "block"
          "blk"
          "flat"
          "hierarchy"
          "include"
          "semimonthly"
          "purpose"
          "midGoal"
          "nearGoal"
          "focus"
          "project"
          "daily"
          "dinner"
	  "kit"
          "maint"
          "manuscript"
          "mod"
          "monthly"
	  "poster"
          "present"
          "prog"
          "report"
          "routine"
          "soln"
          "weekly"
          "write"
          "sci_rep"
          "stretch"
          "study"))
;; .TODO

(setq org-todo-keyword-faces
      (quote (("TODO" :background "red")
              ("NEXT" :foreground "black" :background "yellow"))))

;; keep TODO state timestamps in drawer
(setq org-log-into-drawer t)

;; add done timestamp
(setq org-log-done 'time)

;; enforce dependencies
(setq org-enforce-todo-dependencies t)

;; priority levels
(setq org-highest-priority 65)
(setq org-lowest-priority 89)
(setq org-default-priority 89)
;; open in same frame

(setq org-link-frame-setup
      '((vm . vm-visit-folder)
        (vm-imap . vm-visit-imap-folder)
        (gnus . org-gnus-no-new-news)
        (file . find-file)  ;; Open files in the same frame
        (wl . wl)))
;; Set org-file-apps to use xdg-open for all file extensions

(setq org-file-apps
      `((directory . "/usr/bin/gnome-terminal --working-directory=\"%s\"")
        ("\\.pdf\\'" . "setsid -w xdg-open \"%s\"")
        ("\\.pptx\\'" . "setsid -w xdg-open \"%s\"")
        ("\\.svg\\'" . "setsid -w xdg-open \"%s\"")
        ("\\.xlsx\\'" . "setsid -w xdg-open \"%s\"")
        ("\\.org\\'" . emacs)
        ("\\.sty\\'" . emacs)
        ("\\.sh\\'" . emacs)
        ("\\.tex\\'" . emacs)
        ("\\.\\(yaml\\|yml\\|txt\\|md\\|conf\\|list\\|tex\\)\\'" .
         (lambda (file path)
           (start-process "emacsclient" nil
                          "setsid"
                          "/usr/local/bin/emacsclient"
                          "--socket-name" "/home/jeszyman/.emacs.d/server/server"
                          "-c" (expand-file-name file))))
        (t . "setsid -w xdg-open \"%s\"")))
;; ssh: link type

;; Opens a gnome-terminal SSH session. Usage: =[[ssh:jeff-beast][label]]=

(org-link-set-parameters "ssh"
  :follow (lambda (path)
    (start-process "gnome-terminal-ssh" nil
                   "/usr/bin/gnome-terminal" "--" "ssh" path)))
;; Lists

(setq org-cycle-include-plain-lists 'integrate)
(setq org-list-indent-offset 0)
;; Inline images

(setq org-display-inline-images t
      org-startup-with-inline-images t)
;; Tables

;; https://emacs.stackexchange.com/questions/22210/auto-update-org-tables-before-each-export
;; broke tangle?
;; (add-hook 'before-save-hook 'org-table-recalculate-buffer-tables)
(setq org-startup-align-all-tables t)
(setq org-startup-shrink-all-tables t)
;; org-image-actual-width
;; When set as a list as below, 300 pixels will be the default, but another width can be specified through ATTR, e.g. #+ATTR_ORG: :width 800px

(setq org-image-actual-width '(300))
;; Reload inline images after code eval

(add-hook 'org-babel-after-execute-hook #'org-redisplay-inline-images)
;; LaTeX preview

(setq org-format-latex-options (plist-put org-format-latex-options :scale 3))
;; Source code and tangle

;; Stale =.elc= files silently override =.el= source — Emacs's =load= prefers byte-compiled files. After tangling new code into a =.el= file, delete any corresponding =.elc= or recompile. The =public_config.elc= incident (2026-03-18) caused org MCP tools to silently not register for months because the =.elc= predated the registration code.

; For org 9.7
(setq org-babel-tangle-remove-file-before-write 'auto)
;; Default header arguments
;; #+name: babel_default_header_args

(setq org-babel-default-header-args '(
				      (:comments . "no")
				      (:mkdirp . "yes")
				      (:padline . "no")
				      (:results . "silent")
                                      (:cache . "no")
                                      (:eval . "never-export")
                                      (:exports . "none")
                                      (:noweb . "yes")
                                      (:tangle . "no")
                                      (:tangle-mode . #o755)
				      ))
;; General

(setq
 ;; Blocks inserted directly without additional formatting
 org-babel-inline-result-wrap "%s"
 ;;
 ;; Preserve language-specific indentation, aligns left
 org-src-preserve-indentation t
 ;;
 ;; Tab works like in major mode of lanuauge
 org-src-tab-acts-natively t
 ;;
 org-edit-src-content-indentation 0
 ;;
 org-babel-python-command "python3"
 ;;
 org-confirm-babel-evaluate nil
 ;;
 org-src-fontify-natively t
 ;;
 ;; Open src windows in current frames
 org-src-window-setup 'current-window)
;; disable confrmation for elisp execution of org src blocks
(setq safe-local-variable-values '((org-confirm-elisp-link-function . nil)))

(setq org-hide-block-startup t)
;; Toggle collapse blocks

(defvar org-blocks-hidden nil)

(defun org-toggle-blocks ()
  (interactive)
  (if org-blocks-hidden
      (org-show-block-all)
    (org-hide-block-all))
  (setq-local org-blocks-hidden (not org-blocks-hidden)))
;; org-babel-min-lines-for-block-output
;; When executing a source block in org mode with the output set to verbatim, it will sometimes wrap the results in an #begin_example block, and sometimes it uses : symbols at the beginning of the line. Prevented with org-babel-src-preserve-indentation

;; https://emacs.stackexchange.com/questions/39390/force-org-to-use-instead-of-begin-example-for-source-block-output

(setq org-babel-min-lines-for-block-output 1000)
;; Change noweb wrapper symbols

(setq org-babel-noweb-wrap-start "<#"
      org-babel-noweb-wrap-end "#>")
;; Strip properties drawers from tangled output

(defun jg/strip-properties-from-tangle ()
  "Remove tangled :PROPERTIES: drawer comments and collapse excess blank lines."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^;; :PROPERTIES:\n\\(;; .*\n\\)*;; :END:\n" nil t)
      (replace-match ""))
    (goto-char (point-min))
    (while (re-search-forward "\n\\{3,\\}" nil t)
      (replace-match "\n\n")))
  (save-buffer))

(add-hook 'org-babel-post-tangle-hook #'jg/strip-properties-from-tangle)
;; Distinguish Org Edit Special buffers

;; Distinguish Org Edit Special buffers
;;
;; When using `org-edit-special` (C-c '), Org opens the code block
;; in a temporary buffer running `org-src-mode`. By default, this
;; buffer looks almost identical to the main Org buffer, making it
;; hard to tell which context you're in.
;;
;; To fix that, we remap the `default` face inside `org-src-mode`
;; to use a darker tinted background (e.g. "#0d1b2a"). This way,
;; it's visually obvious when you're editing inside the special
;; buffer versus just looking at the block in the Org file.
;;
;; The change is buffer-local and disappears automatically when you
;; exit the special edit view.

(defun my/org-src-buffer-setup ()
  "Change background for org-src buffers to indicate special edit view."
  (face-remap-add-relative 'default '(:background "#1b1f2d"))) ; pick your color

(add-hook 'org-src-mode-hook #'my/org-src-buffer-setup)
;; Header views and cycling

(setq org-show-hierarchy-above t)

(setq org-fold-show-context-detail
      '((default . tree)))
(setq
 org-show-context-detail
 '((agenda . ancestors)
   (bookmark-jump . ancestors)
   (isearch . ancestors)
   (default . ancestors))
)
(defun org-hide-all-src-blocks ()
  "Hide all source blocks in the current Org buffer."
  (interactive)
  (org-babel-map-src-blocks nil
    (save-excursion
      (goto-char (org-babel-where-is-src-block-head))
      (org-hide-block-toggle t))))

(defun my-collapse-all-drawers (&optional arg)
  "Hide all drawers and optionally cycle global visibility.
When called with a prefix ARG (C-u), also cycle global visibility, hide all src blocks, and jump to the beginning of the buffer."
  (interactive "P")
  (org-hide-drawer-all)
  (when arg
    (org-cycle-global)
    (org-hide-all-src-blocks)
    (goto-char (point-min))) ;; Use `goto-char` instead of `beginning-of-buffer` for clarity
  ;; Ensure tags are aligned after all visibility changes
  (org-align-tags t)) ;; Pass `t` to align all tags in the buffer

(global-set-key (kbd "C-c d") 'my-collapse-all-drawers)
;; You might want to remove the hook if you don't want this function to run every time you open an org file
(add-hook 'org-mode-hook 'my-collapse-all-drawers)
;; No blank lines!

(setq org-cycle-separator-lines 0)
(setq yas-indent-line 'fixed)

;; https://chatgpt.com/c/670d4cb7-5c08-8005-bec8-a2800e4bd0c4

;; (defun my-remove-trailing-newlines-in-tangled-blocks ()
;;   "Remove trailing newlines from tangled block bodies."
;;   (save-excursion
;;     (goto-char (point-max))
;;     (when (looking-back "\n" nil)
;;       (delete-char -1))))

;; (add-hook 'org-babel-post-tangle-hook #'my-remove-trailing-newlines-in-tangled-blocks)
;; General

(setq org-confirm-shell-link-function nil)
(with-eval-after-load 'org
        (add-to-list 'org-modules 'org-habit))

;; Clock times in hours and minutes
;;  (see https://stackoverflow.com/questions/22720526/set-clock-table-duration-format-for-emacs-org-mode
(setq org-time-clocksum-format
      '(:hours "%d" :require-hours t :minutes ":%02d" :require-minutes t))
(setq org-duration-format (quote h:mm))

(setq org-catch-invisible-edits 'error)
(global-set-key (kbd "C-c l") 'org-store-link)
(setq org-indirect-buffer-display 'current-window)

(setq org-id-link-to-org-use-id 'use-existing)
;;https://stackoverflow.com/questions/28351465/emacs-orgmode-do-not-insert-line-between-headers

(setq org-enforce-todo-checkbox-dependencies t)
;; don't adapt indentation to header level
(setq org-adapt-indentation nil)

(setq org-support-shift-select t)
(setq org-src-window-setup 'current-window)
(setq org-export-async-debug nil)
;; ensures that any file with the .org extension will automatically open in org-mode
(add-to-list 'auto-mode-alist '("\\.org\\'" . org-mode))
;; Make heading regex include tags
(setq org-heading-regexp "^[[:space:]]*\\(\\*+\\)\\(?: +\\(.*?\\)\\)?[ \t]*\\(:[[:alnum:]_@#%:]+:\\)?[ \t]*$")
;; org-blank-before-new-entry
;; https://stackoverflow.com/questions/28351465/emacs-orgmode-do-not-insert-line-between-headers

(setq org-blank-before-new-entry '((heading . nil) (plain-list-item . nil)))
;; my-org-tree-to-indirect-buffer

(defun my-org-tree-to-indirect-buffer (&optional arg)
  "Open current org tree in indirect buffer, using one prefix argument.
When called with two prefix arguments, ARG, run the original function without prefix argument."
  (interactive "P")
  (if (equal arg '(16)) ; 'C-u C-u' produces (16)
      (org-tree-to-indirect-buffer nil) ; original behavior
    (org-tree-to-indirect-buffer t)) ; one prefix argument
  ;; Defer drawer collapse: org-tree-to-indirect-buffer calls org-show-entry
  ;; internally, which re-opens drawers after the buffer is created. Running
  ;; after the current command cycle ensures we collapse last.
  (run-with-idle-timer 0 nil #'my-collapse-all-drawers))
(define-key org-mode-map (kbd "C-c C-x b") 'my-org-tree-to-indirect-buffer)
;; Export
;; #+name: orgmode_export_general

;; the below as nil fucks of export of inline code
(setq org-export-babel-evaluate t)
;; https://emacs.stackexchange.com/questions/23982/cleanup-org-mode-export-intermediary-file/24000#24000

(with-eval-after-load 'org
  (setq org-export-backends '(ascii html latex odt icalendar md org)))

(setq-default cache-long-scans nil)
(setq org-export-with-broken-links t)
(setq org-export-allow-bind-keywords t)

(setq org-export-with-sub-superscripts nil
      org-export-headline-levels 2
      org-export-with-toc nil
      org-export-with-section-numbers nil
      org-export-with-tags nil
      org-export-with-todo-keywords nil)
(setq org-odt-preferred-output-format "docx")
;; Open URLs in new window with C-u C-c C-o

(defun my-org-open-in-brave-new-window (link)
  "Open the LINK in Brave browser in a new window."
  (start-process "brave-new-window" nil "brave-browser" "--new-window" link))

(defun org-link-frame-open-id-or-file-in-new-frame (link)
  "Open the FILE or ID LINK in a new frame."
  (let ((location (cond
                   ((string= (org-element-property :type (org-element-context)) "id")
                    (org-id-find link 'marker))
                   (t
                    link)))) ; Assume it's a file link directly usable by `find-file-noselect`
    (if (markerp location)
        (with-current-buffer (marker-buffer location)
          (select-frame (make-frame))
          (goto-char location))
      (select-frame (make-frame))
      (find-file link))))

(defun my-org-open-at-point (&optional arg)
  "Open the link at point.
Use a new window in Brave if ARG is non-nil and the link is a URL.
Open in a new Emacs frame if ARG is non-nil for ID or file links.
On citations, use jg/citar-open-smart (PDF > DOI > URL)."
  (interactive "P")
  (let* ((context (org-element-context))
         (etype (org-element-type context))
         (link-type (org-element-property :type context))
         (raw-link (org-element-property :raw-link context))
         (link-path (org-element-property :path context)))
    (cond
     ;; Citation: smart open (PDF > DOI > URL)
     ((memq etype '(citation citation-reference))
      (let ((key (org-element-property :key context)))
        (jg/citar-open-smart key)))
     ;; Prefix arg: special handling for links
     ((and arg link-type)
      (cond
       ((or (string= link-type "http") (string= link-type "https"))
        (my-org-open-in-brave-new-window raw-link))
       ((or (string= link-type "id") (string= link-type "file"))
        (org-link-frame-open-id-or-file-in-new-frame link-path))
       (t
        (message "No special handling for this link type: %s" link-type))))
     ;; Default
     (t (org-open-at-point)))))

;; Rebind C-c C-o in org mode to our custom function
(define-key org-mode-map (kbd "C-c C-o") 'my-org-open-at-point)
;; Checkboxes

;; (defun org-toggle-checkbox-and-children ()
;;   "Toggle checkbox and all children checkboxes."
;;   (interactive)
;;   (save-excursion
;;     (let* ((parent-indent (current-indentation))
;;            (end (save-excursion
;;                   (org-end-of-subtree)
;;                   (point)))
;;            (current-checkbox (save-excursion
;;                              (beginning-of-line)
;;                              (when (re-search-forward "\\[[ X-]\\]" (line-end-position) t)
;;                                (match-string 0))))
;;            (new-state (if (equal current-checkbox "[ ]") "[X]" "[ ]")))
;;       ;; Toggle the parent checkbox
;;       (beginning-of-line)
;;       (when (re-search-forward "\\[[ X-]\\]" (line-end-position) t)
;;         (replace-match new-state))
;;       ;; Toggle all children checkboxes
;;       (forward-line)
;;       (while (< (point) end)
;;         (let ((line-start (point)))
;;           (when (and (> (current-indentation) parent-indent)
;;                     (re-search-forward "\\[[ X-]\\]" (line-end-position) t))
;;             (replace-match new-state)
;;             (goto-char line-start)))
;;         (forward-line 1)))))

;; ;; Bind it to a convenient key
;; (define-key org-mode-map (kbd "C-c x") 'org-toggle-checkbox-and-children)
;; Capture

;; Make C-o a prefix key
(define-prefix-command 'jg-C-o-map)
(global-set-key (kbd "C-o") #'jg-C-o-map)

;; Bind C-o c to org-capture
(define-key jg-C-o-map (kbd "c") #'org-capture)
;; Documentation

(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("documentation"
                 "\\documentclass{article}
                 \\usepackage{/home/jeszyman/repos/latex/sty/documentation}
                 [NO-DEFAULT-PACKAGES]
                 [NO-PACKAGES]
                 [EXTRA]
                 \\tableofcontents"
                 ("\\section{%s}" . "\\section{%s}")
                 ("\\subsection{%s}" . "\\subsection{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection{%s}")
                 ("\\paragraph{%s}" . "\\paragraph{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph{%s}"))))
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("documentation"
                 "\\documentclass{article}
                 \\usepackage{/home/jeszyman/repos/latex/sty/documentation}
                 [NO-DEFAULT-PACKAGES]
                 [NO-PACKAGES]
                 [EXTRA]
                 \\begin{document}
                 \\tableofcontents
                 \\vspace{1cm}"
                 ("\\section{%s}" . "\\section{%s}")
                 ("\\subsection{%s}" . "\\subsection{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection{%s}")
                 ("\\paragraph{%s}" . "\\paragraph{%s}")
                 ("\\subparagraph{%s}" . "\\subparagraph{%s}"))))
;; iCalendar

(setq org-icalendar-with-timestamps 'active)
(setq org-icalendar-use-scheduled t)
(setq org-icalendar-use-deadline nil)
(setq org-icalendar-include-todo t)
(setq org-icalendar-exclude-tags (list "noexport"))
(setq org-icalendar-include-body '1)
(setq org-icalendar-alarm-time '5)
(setq org-icalendar-store-UID t) ;;Required for syncs
(setq org-icalendar-timezone "America/Chicago")
(setq org-agenda-default-appointment-duration 30)
(setq org-icalendar-combined-agenda-file "/tmp/org.ics")
;; Properties

(setq org-use-property-inheritance t)
;; (browse-org-table-urls-by-name)

(defun browse-org-table-urls-by-name (table-name)
  "Browse URLs listed in an Org-mode table identified by TABLE-NAME.
TABLE-NAME is the name of the table identified as #+name."

  (interactive "sEnter table name: ")
  (let* ((element (ignore-errors
                    (org-element-map (org-element-parse-buffer) 'table
                      (lambda (el)
                        (when (string= (org-element-property :name el) table-name)
                          el))
                      nil t))))
    (if (not element)
        (message "Table with name %s not found" table-name)
      (let ((table-begin (org-element-property :contents-begin element))
            (table-end (org-element-property :contents-end element)))
        (if (or (null table-begin) (null table-end))
            (message "No contents found for the table with name %s" table-name)
          (let ((table-content (buffer-substring-no-properties table-begin table-end)))
            (with-temp-buffer
              (insert table-content)
              (goto-char (point-min))
              (let ((urls (org-table-to-lisp)))
                (if (not urls)
                    (message "No URLs found in the table with name %s" table-name)
                  (let ((first-url (car (car urls))))
                    (start-process "brave-browser" nil "brave-browser" "--new-window" first-url)
                    (sit-for 2)  ;; Wait for the new window to open
                    (dolist (url-row (cdr urls))
                      (start-process "brave-browser" nil "brave-browser" (car url-row))
                      (sit-for 0.5)))  ;; Delay between each URL
                  (message "Opened URLs from table with name %s" table))))))))))
;; Agenda

(global-set-key "\C-ca" 'org-agenda)

(setq org-agenda-repeating-timestamp-show-all nil)
(setq org-sort-agenda-notime-is-late nil)
(setq org-agenda-start-on-weekday nil)
(setq org-agenda-remove-tags t)
(setq org-agenda-skip-scheduled-if-done t)

(setq org-agenda-files
      (append
       ;; Always include the main org directory
       (list "~/repos/org/")

       ;; Add .org files from each subdirectory in ~/repos/
       (cl-remove-if-not
        #'file-exists-p  ;; only keep paths that actually exist
        (mapcar (lambda (d)
                  ;; Construct path like ~/repos/foo/foo.org for each subdir ~/repos/foo/
                  (let ((f (expand-file-name
                            (concat (file-name-nondirectory (directory-file-name d)) ".org")
                            d)))
                    f))
                ;; Get all subdirectories (excluding . and ..) in ~/repos/
                (directory-files "~/repos/" t "^[^.]+" t)))))

(setq org-agenda-skip-unavailable-files t)

(setq org-agenda-use-tag-inheritance t)
;;  http://stackoverflow.com/questions/36873727/make-org-agenda-full-screen
(setq org-agenda-window-setup (quote only-window))
(setq org-agenda-todo-ignore-time-comparison-use-seconds t)

;;; Based on http://article.gmane.org/gmane.emacs.orgmode/41427
  (defun my-skip-tag(tag)
    "Skip entries that are tagged TAG"
    (let* ((entry-tags (org-get-tags-at (point))))
      (if (member tag entry-tags)
          (progn (outline-next-heading) (point))
        nil)))
;; Needed for no y/n prompt at linked agenda execution
(setq org-confirm-elisp-link-function nil)
;; :plain link type
;; https://claude.ai/chat/c775f0eb-fa91-45b4-82d6-e1a0df8b5526
;; #+name: org_plain_links

(defun org-plain-follow (id _)
  "Follow a plain link as if it were an ID link."
  (interactive "sOrg ID: ")
  (org-id-open id nil))

(defun org-plain-export (link description format info)
  "Exports a plain link.
   - For 'org' format (internal Org buffer display), show full link.
   - For final external exports (HTML, LaTeX, ASCII), show only the description."
  ;; 'link' is the path part (e.g., "5827ecc7-04d7-4af4-8844-4e68d1b38aca")
  ;; 'description' is the label (e.g., "No social media")
  (pcase format
    ;; If the format is 'org' (for internal Org conversion/display,
    ;; typically what org-babel uses for :results table)
    ('org
     (format "[[plain:%s][%s]]" link description)) ; Reconstruct the full Org link

    ;; For standard export backends (HTML, LaTeX, ASCII)
    ((or 'html 'latex 'ascii)
     (or description link)) ; Return only the description (label), or link if no description

    ;; For any other format (fallback), just return the description or link
    (_ (or description link))))

(org-link-set-parameters "plain"
                         :follow #'org-plain-follow
                         :complete #'org-id-complete ; Optional, but good for consistency
                         :export #'org-plain-export  ; Point to this refined export function
                         :face 'org-link) ; Optional: Style the link like other Org links

(provide 'ol-plain)

(with-eval-after-load 'org
  (require 'ol-plain))
;; org-image-actual-width
;; When set as a list as below, 300 pixels will be the default, but another width can be specified through ATTR, e.g. #+ATTR_ORG: :width 800px

(setq org-image-actual-width '(300))
;; Checkbox intermediate states!

;; https://claude.ai/chat/81ca7e51-65b4-4c0d-892b-a94861979890

;; Enhanced Org mode checkbox toggling with three states
;; States: [ ] (empty) -> [-] (partial/in-progress) -> [X] (done) -> [ ] (cycle)
;; Fixed to work correctly with nested checkboxes and prefix arguments

(defun my/get-list-item-indentation ()
  "Get the indentation level of the current list item."
  (save-excursion
    (beginning-of-line)
    (if (looking-at "^\\(\\s-*\\)\\([-+*]\\|[0-9]+[.)]\\)")
        (length (match-string 1))
      0)))

(defun my/find-parent-checkbox ()
  "Find the parent checkbox of the current item, if any."
  (let ((current-indent (my/get-list-item-indentation)))
    (save-excursion
      (forward-line -1)
      (while (and (not (bobp))
                  (or (not (looking-at "^\\s-*\\([-+*]\\|[0-9]+[.)]\\)"))
                      (>= (my/get-list-item-indentation) current-indent)))
        (forward-line -1))
      (when (and (looking-at "^\\s-*\\([-+*]\\|[0-9]+[.)]\\)")
                 (< (my/get-list-item-indentation) current-indent)
                 (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t))
        (point-at-bol)))))

(defun my/get-child-checkboxes (parent-line)
  "Get all child checkboxes of the given parent line."
  (let ((parent-indent (save-excursion
                         (goto-char parent-line)
                         (my/get-list-item-indentation)))
        (children '()))
    (save-excursion
      (goto-char parent-line)
      (forward-line 1)
      (while (and (not (eobp))
                  (or (looking-at "^\\s-*$")  ; blank line
                      (> (my/get-list-item-indentation) parent-indent)))
        (when (and (looking-at "^\\s-*\\([-+*]\\|[0-9]+[.)]\\)")
                   (= (my/get-list-item-indentation) (+ parent-indent 2))  ; direct children
                   (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t))
          (push (match-string 1) children))
        (forward-line 1)))
    (reverse children)))

(defun my/update-parent-checkbox (parent-line)
  "Update parent checkbox based on children states."
  (let ((children (my/get-child-checkboxes parent-line)))
    (when children
      (let ((all-checked (cl-every (lambda (state) (string= state "X")) children))
            (none-checked (cl-every (lambda (state) (string= state " ")) children))
            (some-partial (cl-some (lambda (state) (string= state "-")) children)))
        (save-excursion
          (goto-char parent-line)
          (when (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)
            (let ((checkbox-start (match-beginning 0)))
              (goto-char checkbox-start)
              (delete-char 3)
              (cond
               (all-checked (insert "[X]"))
               ((or some-partial (not none-checked)) (insert "[-]"))
               (t (insert "[ ]"))))))))))

(defun my/has-child-checkboxes (line)
  "Check if the given line has child checkboxes. Simple version."
  (let ((parent-indent (save-excursion
                         (goto-char line)
                         (my/get-list-item-indentation))))
    (save-excursion
      (goto-char line)
      (forward-line 1)
      ;; Look at the very next non-empty line
      (while (and (not (eobp))
                  (looking-at "^\\s-*$"))
        (forward-line 1))
      ;; If the next line exists and is more indented with a checkbox, we have a child
      (and (not (eobp))
           (looking-at "^\\s-*\\([-+*]\\|[0-9]+[.)]\\)")
           (> (my/get-list-item-indentation) parent-indent)
           (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)))))

(defun my/org-toggle-checkbox-three-state (&optional use-three-states)
  "Toggle checkbox with three states: [ ], [-], [X].
If USE-THREE-STATES is non-nil, cycle through all three states.
Otherwise, use default Org behavior ([ ] <-> [X]).
Automatically updates parent checkboxes.
Parent checkboxes with children cannot be directly toggled."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)
      (let ((current-state (match-string 1))
            (checkbox-start (match-beginning 0))
            (current-line (point-at-bol)))
        ;; Debug: let's temporarily disable the parent check to see if basic functionality works
        ;; (if (my/has-child-checkboxes current-line)
        ;;     (message "Cannot toggle parent checkbox directly - toggle children instead")
        (progn
          (goto-char checkbox-start)
          (cond
           ;; With three-state mode, cycle through all states
           (use-three-states
            (cond
             ((string= current-state " ")
              (delete-char 3)
              (insert "[-]"))
             ((string= current-state "-")
              (delete-char 3)
              (insert "[X]"))
             ((string= current-state "X")
              (delete-char 3)
              (insert "[ ]"))))
           ;; Without three-state mode, use default behavior (empty <-> checked)
           (t
            (cond
             ((string= current-state " ")
              (delete-char 3)
              (insert "[X]"))
             ((string= current-state "X")
              (delete-char 3)
              (insert "[ ]"))
             ((string= current-state "-")
              (delete-char 3)
              (insert "[X]")))))
          ;; Update parent checkbox if it exists
          (let ((parent-line (my/find-parent-checkbox)))
            (when parent-line
              (my/update-parent-checkbox parent-line)))
          ;; Update statistics cookies (e.g., [0%] or [/])
          (org-update-checkbox-count-maybe)
          (when (org-at-heading-p)
            (org-update-parent-todo-statistics)))))))

;; Alternative function that always cycles through three states
(defun my/org-cycle-checkbox-three-state ()
  "Always cycle through three checkbox states: [ ] -> [-] -> [X] -> [ ]"
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)
      (let ((current-state (match-string 1))
            (checkbox-start (match-beginning 0)))
        (goto-char checkbox-start)
        (cond
         ((string= current-state " ")
          (delete-char 3)
          (insert "[-]"))
         ((string= current-state "-")
          (delete-char 3)
          (insert "[X]"))
         ((string= current-state "X")
          (delete-char 3)
          (insert "[ ]")))))))

;; Helper function to check if we're on a checkbox line
(defun my/org-on-checkbox-line-p ()
  "Return t if current line contains a checkbox."
  (save-excursion
    (beginning-of-line)
    (re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)))

;; Custom command that handles prefix arguments properly
(defun my/org-checkbox-dwim ()
  "Do what I mean with checkboxes.
With no prefix: toggle between [ ] and [X]
With C-u prefix: cycle through [ ], [-], [X]"
  (interactive)
  (if (my/org-on-checkbox-line-p)
      (my/org-toggle-checkbox-three-state current-prefix-arg)
    (org-ctrl-c-ctrl-c)))

;; Setup the keybindings
(with-eval-after-load 'org
  ;; Ensure cl-lib is available for cl-every and cl-some
  (require 'cl-lib)

  ;; Method 1: Replace C-c C-c entirely for checkbox lines
  (defun my/org-ctrl-c-ctrl-c-replacement ()
    "Replacement for C-c C-c that handles three-state checkboxes."
    (interactive)
    (if (my/org-on-checkbox-line-p)
        (my/org-toggle-checkbox-three-state current-prefix-arg)
      (call-interactively #'org-ctrl-c-ctrl-c)))

  ;; Bind our custom command
  (define-key org-mode-map (kbd "C-c C-c") #'my/org-ctrl-c-ctrl-c-replacement)

  ;; Optional: Add a direct keybinding for the three-state cycle
  (define-key org-mode-map (kbd "C-c C-x c") #'my/org-cycle-checkbox-three-state))

;; Alternative Method 2: Using advice (uncomment if you prefer this approach)
;; (with-eval-after-load 'org
;;   (defun my/org-ctrl-c-ctrl-c-advice (orig-fun &rest args)
;;     "Advice for org-ctrl-c-ctrl-c to handle three-state checkboxes."
;;     (if (my/org-on-checkbox-line-p)
;;         (my/org-toggle-checkbox-three-state current-prefix-arg)
;;       (apply orig-fun args)))
;;
;;   (advice-add 'org-ctrl-c-ctrl-c :around #'my/org-ctrl-c-ctrl-c-advice))

;; Enhanced version that also handles creation of new checkboxes
(defun my/org-toggle-checkbox-enhanced (&optional use-three-states)
  "Toggle checkbox or create one if none exists.
If USE-THREE-STATES is non-nil, cycle through all three states."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (cond
     ;; If there's already a checkbox, toggle it
     ((re-search-forward "\\[\\([X -]\\)\\]" (line-end-position) t)
      (let ((current-state (match-string 1))
            (checkbox-start (match-beginning 0)))
        (goto-char checkbox-start)
        (cond
         (use-three-states
          (cond
           ((string= current-state " ")
            (delete-char 3)
            (insert "[-]"))
           ((string= current-state "-")
            (delete-char 3)
            (insert "[X]"))
           ((string= current-state "X")
            (delete-char 3)
            (insert "[ ]"))))
         (t
          (cond
           ((string= current-state " ")
            (delete-char 3)
            (insert "[X]"))
           ((or (string= current-state "X") (string= current-state "-"))
            (delete-char 3)
            (insert "[ ]")))))))
     ;; If on a list item without checkbox, create one
     ((save-excursion
        (beginning-of-line)
        (re-search-forward "^\\s-*\\([-+*]\\|[0-9]+[.)]\\)\\s-+" (line-end-position) t))
      (goto-char (match-end 0))
      (insert "[ ] ")))))

;; Optional: Visual enhancement - different faces for different states
(with-eval-after-load 'org
  (font-lock-add-keywords
   'org-mode
   '(("\\(\\[X\\]\\)" 1 '(:foreground "green" :weight bold))
     ("\\(\\[-\\]\\)" 1 '(:foreground "orange" :weight bold))
     ("\\(\\[ \\]\\)" 1 '(:foreground "red")))))

;; Usage instructions:
;; Method used: Direct key replacement
;; 1. C-c C-c on checkbox: toggles between [ ] and [X] (default behavior)
;; 2. C-u C-c C-c on checkbox: cycles through [ ] -> [-] -> [X] -> [ ]
;; 3. C-c C-x c: always cycles through all three states
;; 4. C-c C-c on non-checkbox: normal org-ctrl-c-ctrl-c behavior
;; org-sleeper

;; Emacs idle timer trigger for the org-sleeper autonomous linter. One-shot idle timer fires after 600s of idle, launches the gate script, and a process sentinel re-arms a new timer when the run finishes. The =process-live-p= guard prevents pile-up if the timer fires while a run is active.

(defvar my/org-sleeper-process nil
  "Process object for the current org-sleeper run.")

(defun my/org-sleeper-rearm ()
  "Schedule next org-sleeper run after 600s idle."
  (run-with-idle-timer 600 nil #'my/org-sleeper-trigger))

(defun my/org-sleeper-trigger ()
  "Launch org-sleeper gate script if no run is active, re-arm on exit."
  (if (and my/org-sleeper-process
           (process-live-p my/org-sleeper-process))
      ;; Previous run still active — re-arm to try again later
      (my/org-sleeper-rearm)
    (setq my/org-sleeper-process
          (start-process "org-sleeper" nil
            "/bin/bash" (expand-file-name "~/repos/org/scripts/org-sleeper.sh")))
    (set-process-sentinel my/org-sleeper-process
      (lambda (_proc _event) (my/org-sleeper-rearm)))))

(when (string= (system-name) "jeff-beast")
  (my/org-sleeper-rearm))
;; org-sleeper

;; Emacs idle timer trigger for the org-sleeper autonomous linter. One-shot idle timer fires after 600s of idle, launches the gate script, and a process sentinel re-arms a new timer when the run finishes. The =process-live-p= guard prevents pile-up if the timer fires while a run is active.

(defvar my/org-sleeper-process nil
  "Process object for the current org-sleeper run.")

(defun my/org-sleeper-rearm ()
  "Schedule next org-sleeper run after 600s idle."
  (run-with-idle-timer 600 nil #'my/org-sleeper-trigger))

(defun my/org-sleeper-trigger ()
  "Launch org-sleeper gate script if no run is active, re-arm on exit."
  (if (and my/org-sleeper-process
           (process-live-p my/org-sleeper-process))
      ;; Previous run still active — re-arm to try again later
      (my/org-sleeper-rearm)
    (setq my/org-sleeper-process
          (start-process "org-sleeper" nil
            "/bin/bash" (expand-file-name "~/repos/org/scripts/org-sleeper.sh")))
    (set-process-sentinel my/org-sleeper-process
      (lambda (_proc _event) (my/org-sleeper-rearm)))))

(when (string= (system-name) "jeff-beast")
  (my/org-sleeper-rearm))
;; Editing text

;;https://emacs.stackexchange.com/questions/12701/kill-a-line-deletes-the-line-but-leaves-a-blank-newline-character
(setq kill-whole-line t)
;; bibtex

(setq reftex-default-bibliography '("~/repos/org/bib.bib"))

;; see org-ref for use of these variables

(setq bibtex-completion-bibliography "~/repos/org/bib.bib"
      bibtex-completion-library-path "~/library"
      bibtex-completion-notes-path "~/repo/org/notes")
;; get-bibtex-from-doi

(defun get-bibtex-from-doi (dois-string)
  "Get BibTeX entry or entries from one or more DOIs and insert them at point.
You can enter multiple DOIs separated by spaces.

For each DOI, if an entry with the same DOI is already present in
the current buffer (based on a `doi = {…}` field), that DOI is
skipped and nothing is inserted for it."
  (interactive "MDOI (space-separated for multiple): ")
  ;; Split the minibuffer input on whitespace into a list of DOIs.
  (let ((dois (split-string dois-string "[ \t\n]+" t)))
    (dolist (doi dois)
      ;; Normalize DOI: strip http(s)://(dx.)doi.org/ if present.
      (let* ((normalized-doi
              (replace-regexp-in-string
               "\\`https?://\\(dx\\.\\)?doi\\.org/" "" doi))
             (doi-field-regexp
              (concat "doi[[:space:]]*=[[:space:]]*[{\"]"
                      (regexp-quote normalized-doi)
                      "[}\"]")))
        ;; Check whether this DOI already exists in the current buffer.
        (if (save-excursion
              (goto-char (point-min))
              (re-search-forward doi-field-regexp nil t))
            (message "Entry with DOI %s already exists in this buffer, skipping"
                     normalized-doi)
          ;; Otherwise, fetch and insert it.
          (let ((url-mime-accept-string "text/bibliography;style=bibtex")
                bibtex-entry
                entry)
            ;; Retrieve BibTeX text from dx.doi.org.
            (let ((buf (url-retrieve-synchronously
                        (format "http://dx.doi.org/%s" normalized-doi))))
              (unless buf
                (error "Could not retrieve DOI %s" normalized-doi))
              (with-current-buffer buf
                (goto-char (point-max))
                (setq bibtex-entry
                      (buffer-substring
                       (string-match "@" (buffer-string))
                       (point))))
              (kill-buffer buf))
            ;; Decode and postprocess the BibTeX entry.
            (setq entry (decode-coding-string bibtex-entry 'utf-8))
            ;; Build key = first-author-lastname + year, e.g. tomczak2024.
            (when (string-match "author={\\([^,{}]+\\)" entry)
              (let* ((first-author (match-string 1 entry))
                     (lastname (replace-regexp-in-string "[^a-zA-Z]" "" first-author)))
                (when (string-match "year={\\([0-9]+\\)" entry)
                  (let* ((year (match-string 1 entry))
                         (new-key (downcase (concat lastname year))))
                    (setq entry
                          (replace-regexp-in-string
                           "@\\(\\w+\\){[^,]+,"
                           (format "@\\1{%s," new-key)
                           entry))))))
            ;; Insert and format this one entry at point.
            (insert entry "\n\n")
            (bibtex-fill-entry)))))))
;; python.el
;; https://github.com/gregsexton/ob-ipython/issues/28

(setq python-shell-completion-native-enable nil)

(add-hook 'python-mode-hook
  (lambda () (setq indent-tabs-mode nil)))

(setq python-indent-guess-indent-offset-verbose nil)
;; UTF8

(set-buffer-file-coding-system 'utf-8)
(prefer-coding-system 'utf-8)
(set-language-environment "UTF-8")
;; Alpha key

(global-set-key (kbd "C-x a") (lambda () (interactive) (insert "α")))
;; AUCTeX
;; - [[https://www.gnu.org/software/auctex/manual/auctex.html#Quick-Start][documentation]]
;;   - [[https://www.gnu.org/software/auctex/manual/auctex/Folding.html][3.2 Folding Macros and Environments]]
;; - https://stackoverflow.com/questions/7587287/how-do-i-bind-latexmk-to-one-key-in-emacs-and-have-it-show-errors-if-there-are-a
;; - [[https://www.gnu.org/software/auctex/manual/auctex.html#Quick-Start][Quick start]]
;; - [[https://tex.stackexchange.com/questions/145318/how-to-make-auctex-not-prompt-me-on-c-c-c-c][stack:tex: How to make auctex not prompt me on C-c C-c]]
;; - [[https://tex.stackexchange.com/questions/20843/useful-shortcuts-or-key-bindings-or-predefined-commands-for-emacsauctex][stack:tex: Useful shortcuts or key bindings or predefined commands for emacs+AUCTeX]]
;; - https://piotrkazmierczak.com/2010/emacs-as-the-ultimate-latex-editor/

(use-package tex
  :ensure auctex
  :config
  (setenv "PATH" (concat "/usr/local/texlive/2021/bin/x86_64-linux:"
			 (getenv "PATH")))
  (add-to-list 'exec-path "/usr/local/texlive/2021/bin/x86_64-linux")
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-save-query nil
        TeX-view-program-selection '((output-pdf "Okular"))
        TeX-view-program-list '(("Okular" "okular %o"))))
(eval-after-load "tex"
  '(progn
     (add-to-list 'TeX-command-list
       '("LatexMk"
         "latexmk -pdf -f -pdflatex=pdflatex -shell-escape -interaction=nonstopmode %s"
         TeX-run-TeX nil t
         :help "Run LatexMk to build PDF"))
     (setq TeX-command-default "LatexMk")))

(eval-after-load "tex"
  '(progn
     (add-to-list 'TeX-command-list
       '("LatexMk"
         "latexmk -pdf -f -pdflatex=pdflatex -shell-escape -interaction=nonstopmode %s"
         TeX-run-TeX nil t
         :help "Run LatexMk to build PDF"))
     (setq TeX-command-default "LatexMk")
     (setq TeX-view-program-selection '((output-pdf "Okular")))
     (setq TeX-view-program-list
           '(("Okular" ("okular --unique %o"))))))
;; Avy
;; [[https://github.com/abo-abo/avy][github: abo-abo/avy]] | [[https://karthinks.com/software/avy-can-do-anything/][Avy can do anything (karthinks)]]

(use-package avy
  :ensure t
  :config
  (defun avy-action-embark (pt)
    (unwind-protect
        (save-excursion
          (goto-char pt)
          (embark-act))
      (select-window
       (cdr (ring-ref avy-ring 0))))
    t)
  (setf (alist-get ?. avy-dispatch-alist) 'avy-action-embark)
  (defun avy-action-mark-word (pt)
    "Mark the whole word at PT."
    (goto-char pt)
    (mark-word 1)
    (activate-mark))
  (setf (alist-get ?m avy-dispatch-alist) 'avy-action-mark-word)
  (key-chord-mode 1)
  (key-chord-define-global "jj" 'avy-goto-char-timer))
;; Casual-avy
;; [[https://github.com/kickingvegas/casual-avy][github: kickingvegas/casual-avy]]

(use-package casual-avy
  :ensure t)
;; Use-package

(use-package blacken
  :after elpy
  :hook (elpy-mode . blacken-mode))
;; citar

;; Citar configuration for org-cite integration
(use-package citar
  :after org
  :init
  (require 'oc)  ;; Ensure org-cite is loaded before configuring citar

  :custom
  ;; Bibliography paths
  (org-cite-global-bibliography '("/home/jeszyman/repos/org/bib.bib"))
  (citar-bibliography org-cite-global-bibliography)
  (citar-library-paths '("~/library/"))   ;; PDF storage

  ;; Set citation processors
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)

  ;; Display formatting
  (citar-display-transform-functions '((t . citar-clean-string)))

  (citar-templates
   '((main . "${author editor:30%sn}     ${date year issued:4}     ${title:48}")
     (suffix . "          ${=key= id:15}    ${=type=:12}    ${tags keywords:*}")
     (preview . "${author editor:%etal} (${year issued date}) ${title}, ${journal journaltitle publisher container-title collection-title}.\n")
     (note . "Notes on ${author editor:%etal}, ${title}")))

  ;; Visual configuration
  (citar-symbols `((file . ?)))  ;; Icon for PDFs only

  ;; Open PDFs and BibTeX entries
  (citar-open-functions
   '((file . (lambda (fpath) (call-process (if (eq system-type 'darwin) "open" "xdg-open") nil 0 nil fpath)))
     (bibtex . citar-open-bibtex-entry)))  ;; Add BibTeX option

  :config
  (define-key org-mode-map (kbd "C-c ]") 'org-cite-insert))

;; Configure file opening for citar
(setq citar-file-open-functions
      '(("html" . citar-file-open-external)
        ("pdf" . citar-file-open-external)  ;; Use system default for PDFs
        (t . find-file)))                   ;; Default to Emacs for others

(require 'oc-biblatex)

(setq org-cite-biblatex-styles
      '((nil nil "autocite" "autocites")   ;; DEFAULT: [cite:@key] -> \autocite{}
        ("auto" nil "autocite" "autocites")
        ("plain" nil "cite" "cites")))     ;; [cite/plain:@key] -> \cite{}
(use-package embark
  :ensure t
  :demand t
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command)
  :config
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

(use-package embark-consult
  :ensure t
  :after embark consult
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(use-package citar-embark
  :after citar embark
  :no-require
  :config (citar-embark-mode))

(defun jg/citar-open-doi (citekey)
  "Open the DOI for CITEKEY in a browser."
  (let ((doi (citar-get-value "doi" citekey)))
    (if doi
        (browse-url (concat "https://doi.org/" doi))
      (message "No DOI found for %s" citekey))))

(defun jg/citar-open-smart (citekey)
  "Open CITEKEY: existing PDF if available, else DOI, else URL."
  (let* ((files-ht (citar-get-files citekey))
         (file-list (when (hash-table-p files-ht)
                      (let (all) (maphash (lambda (_k v) (setq all (append v all))) files-ht) all)))
         (existing (seq-filter #'file-exists-p file-list))
         (doi (citar-get-value "doi" citekey))
         (url (citar-get-value "url" citekey)))
    (cond
     (existing (citar-file-open (car existing)))
     (doi (browse-url (concat "https://doi.org/" doi)))
     (url (browse-url url))
     (t (message "No PDF, DOI, or URL found for %s" citekey)))))

(setq citar-at-point-function 'jg/citar-open-smart)

(with-eval-after-load 'citar-embark
  (keymap-set citar-embark-citation-map "o" #'citar-open-files)
  (keymap-set citar-embark-citation-map "d" #'jg/citar-open-doi))

(advice-add 'citar-file--parse-file-field :around
            (lambda (orig &rest args)
              (let ((inhibit-message t))
                (apply orig args))))

;; https://blog.tecosaur.com/tmio/2021-07-31-citations.html
;; https://kristofferbalintona.me/posts/202206141852/

(setq org-cite-biblatex-styles
      '(("auto" "autocite" "Autocite")
        ("plain" "cite" "Cite")))

(setq org-cite-biblatex-default-style "auto")
;; Conda
;; - https://github.com/necaris/conda.el

;; M-x conda-env-activate

;; Remove everything and evaluate this clean version:
(use-package conda
  :ensure t
  :init
  (setq conda-anaconda-home (expand-file-name "~/miniconda3"))
  (setq conda-env-home-directory (expand-file-name "~/miniconda3"))
  :config
  ;; Tell conda to be quiet
  (setenv "CONDA_VERBOSITY" "0")

  ;; Initialize shells
  (conda-env-initialize-interactive-shells)
  (conda-env-initialize-eshell)

  ;; DO NOT enable autoactivate
  (conda-env-autoactivate-mode -1))

;; Silence the elisp-level messages
(with-eval-after-load 'conda
  (defun conda--message (&rest _args)
    "Suppress all conda messages."
    nil))
(defun my/ess-use-conda-r ()
  "Set `inferior-ess-r-program` to Conda's R if a Conda env is active."
  (when (and (boundp 'conda-env-current-path)
             conda-env-current-path
             (file-exists-p (expand-file-name "bin/R" conda-env-current-path)))
    (setq inferior-ess-r-program
          (expand-file-name "bin/R" conda-env-current-path))))

(with-eval-after-load 'ess-r-mode
  (add-hook 'ess-r-mode-hook #'my/ess-use-conda-r))
;; Corfu

;; Corfu for completion UI
(use-package corfu
  :ensure t
  :init
  (global-corfu-mode) ;; Enable globally
  :custom
  (corfu-auto t)               ;; Enable auto completion
  (corfu-auto-prefix 2)        ;; Start completing after typing 2 characters
  (corfu-auto-delay 1.0)       ;; Delay before suggestions pop up
  :config
  ;; Free up keybindings for `completion-at-point`
  (with-eval-after-load 'flyspell
    (define-key flyspell-mode-map (kbd "C-M-i") nil)
    (define-key flyspell-mode-map (kbd "M-TAB") nil)
    (define-key flyspell-mode-map (kbd "C-.") nil)
    (define-key flyspell-mode-map (kbd "C-;") nil))
  (global-set-key (kbd "M-TAB") #'completion-at-point)) ;; Bind `M-TAB` globally
;; Hide M-x commands irrelevant to the current mode
(use-package emacs
  :custom
  (read-extended-command-predicate #'command-completion-default-include-p))
;; Cape
;; [[https://github.com/minad/cape][github: minad/cape]]

(use-package cape
  :ensure t
  :after corfu
  :config
  (defun my/cape-org-setup ()
    (add-to-list 'completion-at-point-functions #'cape-dabbrev)
    (add-to-list 'completion-at-point-functions #'cape-file)
    (add-to-list 'completion-at-point-functions #'cape-dict)
    (add-to-list 'completion-at-point-functions #'cape-tex))
  (add-hook 'org-mode-hook #'my/cape-org-setup))
;; Dabbrev

;; Dynamic abbreviation completion
(use-package dabbrev
  :ensure nil
  :config
  (setq dabbrev-case-fold-search t) ;; Case-insensitive search
  (setq dabbrev-upcase-means-case-search t)) ;; Respect case for uppercase words
;; Eglot

(use-package eglot
  :ensure t
  :init
  (add-hook 'sh-mode-hook 'eglot-ensure)
  (add-hook 'ess-r-mode-hook 'eglot-ensure)
  (add-hook 'python-mode-hook 'eglot-ensure)
  :config
  (setq eglot-autoshutdown t)
  (setq eglot-sync-connect 0)
  (add-to-list 'eglot-server-programs '(sh-mode . ("bash-language-server" "start")))
  (add-to-list 'eglot-server-programs '(python-mode . ("pylsp")))
  (add-to-list 'eglot-server-programs '(ess-r-mode . ("R" "--slave" "-e" "languageserver::run()"))))

(with-eval-after-load 'eglot
  (define-key eglot-mode-map (kbd "C-c <tab>") #'company-complete))
;; eglot example
(add-to-list 'eglot-server-programs
             '((yaml-mode yaml-ts-mode) . ("yaml-language-server" "--stdio")))
;; Elpy

;; - Prereqs: conda activate base; pip install python-lsp-server[all]
;; - Config does: enables Elpy in python-mode, sets PATH/exec-path to miniconda, WORKON_HOME to ~/miniconda3/envs, forces Elpy RPC python, swaps Flymake → Flycheck, adds ESS-style keys (C-c C-n step, C-c C-b buffer), opens *Python* in new frame.
;; - Workflow: activate env (basecamp etc.), open .py file, Elpy starts, use keybindings to send code, Flycheck handles linting.
;; - Checks: PATH includes miniconda3/bin, elpy-rpc-python-command points to miniconda3/bin/python, Flycheck installed, conda info --envs shows envs.
;; - References: Elpy docs (editing, IDE/REPL, virtual envs), Emacs StackExchange thread on conda conflicts.

;; -------------------------------------------------------------------
;; Elpy — Python IDE inside Emacs
;;
;; Requirements (one-time, in shell):
;;   conda activate base
;;   pip install 'python-lsp-server[all]'
;;
;; This config:
;;   - Enables Elpy automatically in python-mode
;;   - Puts miniconda on PATH and sets WORKON_HOME
;;   - Uses Flycheck instead of Flymake
;;   - Adds ESS-style keybindings for consistency
;;   - Opens Python shell in a new frame when sending code
;; -------------------------------------------------------------------

(use-package elpy
  :init
  ;; Ensure Elpy starts when python-mode starts
  ;; Using advice so elpy-enable runs *before* python-mode setup
  (advice-add 'python-mode :before #'elpy-enable)

  ;; --- Environment setup ---
  ;; Put miniconda bin first on PATH (for `python`, `pip`, etc.)
  (setenv "PATH" (concat (expand-file-name "~/miniconda3/bin") ":" (getenv "PATH")))
  ;; Add same path to exec-path so Emacs subprocesses (compilation, shell, etc.) see it
  (setq exec-path (append (list (expand-file-name "~/miniconda3/bin")) exec-path))

  ;; Tell Elpy where your conda/virtualenv environments live
  (setenv "WORKON_HOME" (expand-file-name "~/miniconda3/envs"))

  ;; RPC backend: force Elpy to use miniconda’s python
  (setq elpy-rpc-python-command (expand-file-name "~/miniconda3/bin/python"))

  ;; Ensure Python processes use UTF-8 encoding
  (add-to-list 'process-coding-system-alist '("python" . (utf-8 . utf-8)))

  :config
  ;; --- Keybindings ---
  ;; Match ESS and essh style: send statement or buffer
  (define-key elpy-mode-map (kbd "C-c C-n") #'elpy-shell-send-statement-and-step)
  (define-key elpy-mode-map (kbd "C-c C-b") #'elpy-shell-send-buffer)

  ;; --- Python shell in new frame ---
  ;; Function to pop up *Python* buffer in a separate frame
  (defun my-elpy-shell-display-buffer-in-new-frame (buffer alist)
    "Display the Python shell BUFFER in a new frame."
    (let ((display-buffer-alist '(("*Python*" display-buffer-pop-up-frame))))
      (display-buffer buffer alist)))

  ;; Wrap elpy’s send-statement-and-step so Python shell opens in new frame
  (advice-add 'elpy-shell-send-statement-and-step :around
              (lambda (orig-fun &rest args)
                (let ((display-buffer-alist
                       '(("*Python*" . (my-elpy-shell-display-buffer-in-new-frame)))))
                  (apply orig-fun args))))

  ;; --- Error checking ---
  ;; Replace Flymake with Flycheck if available (more features, async)
  (when (require 'flycheck nil t)
    (setq elpy-modules (delq 'elpy-module-flymake elpy-modules))
    (add-hook 'elpy-mode-hook #'flycheck-mode)))
;; ESS

;; - Session prompt behavior: ESS only asks "which R session?" once per interactive REPL
;;   window (zero times if the session was launched directly via e.g. =R= or =julia=).
;;   Subsequent evals in the same ESS window reuse that session silently. Potentially
;;   replicable for =ESSshell= (shell REPL) — investigate whether the same
;;   =ess-ask-for-ess-directory= / process-association mechanism applies there.
;; - no python support- https://github.com/emacs-ess/ESS/issues/910
;; - ess-remote to docker R
;; https://www.reddit.com/r/emacs/comments/op4fcm/send_command_to_vterm_and_execute_it/
;; - [[id:3BC3B329-C75B-461C-A4BD-E565C2046424][My ESS config]]
;; - for ESS- https://github.com/emacs-ess/ESS/issues/144
;; - Emacs Speaks Statistics (ess)
;;   - https://github.com/emacs-ess/ESS
;;   - https://ess.r-project.org/
;;   - [[http://ess.r-project.org/Manual/ess.html][documentation]]
;; - ess docker solutions
;;   - https://gtown-ds.netlify.app/2017/08/16/docker-emacs/
;; - http://ess.r-project.org/Manual/ess.html#Activating-and-Loading-ESS
;; - cite:rossini2016
;; - https://stat.ethz.ch/pipermail/ess-help/2010-January/005822.html
;; - https://github.com/emacs-lsp/lsp-mode/issues/1383

(use-package ess
  :ensure t
  :init
  (setq ess-ask-for-ess-directory nil
        ess-help-own-frame 'one
        ess-indent-with-fancy-comments nil
        ess-use-auto-complete t
        ess-use-company t
        inferior-ess-own-frame t
        inferior-ess-same-window nil)
  :mode (("/R/.*\\.q\\'"       . ess-r-mode)
         ("\\.[rR]\\'"         . ess-r-mode)
         ("\\.[rR]profile\\'"  . ess-r-mode)
         ("NAMESPACE\\'"       . ess-r-mode)
         ("CITATION\\'"        . ess-r-mode)
         ("\\.[Rr]out"         . R-transcript-mode)
         ("\\.Rd\\'"           . Rd-mode))
  :hook
  (ess-r-mode . (lambda ()
                 (local-set-key (kbd "C-c C-n") #'ess-eval-line-and-step))))

(custom-set-variables
 '(ess-R-font-lock-keywords
   '((ess-R-fl-keyword:modifiers . t)
     (ess-R-fl-keyword:fun-defs . t)
     (ess-R-fl-keyword:keywords . t)
     (ess-R-fl-keyword:assign-ops . t)
     (ess-R-fl-keyword:constants . t)
     (ess-fl-keyword:fun-calls . t)
     (ess-fl-keyword:numbers . t)
     (ess-fl-keyword:operators . t)
     (ess-fl-keyword:delimiters . t)
     (ess-fl-keyword:= . t)
     (ess-R-fl-keyword:F&T . t)
     (ess-R-fl-keyword:%op% . t))))
;; exec-path-from-shell
;; - Ensures parts of Emacs inherit shell PATH when Emacs is runnng as a daemon

;; -----------------------------------------------------------------------------
;; Shell environment integration
;; -----------------------------------------------------------------------------
;; GUI Emacs doesn't inherit shell environment variables since it's not
;; launched from an interactive shell. exec-path-from-shell fixes this by
;; spawning a shell and importing specified variables.
;;
;; Variables imported:
;;   - PATH, MANPATH (defaults)
;;   - TEXINPUTS: LaTeX package search path (for ~/repos/latex/sty)
;; -----------------------------------------------------------------------------
(use-package exec-path-from-shell
  :ensure t
  :config
  (add-to-list 'exec-path-from-shell-variables "TEXINPUTS")
  (exec-path-from-shell-initialize))
;; expand-region
;; https://github.com/magnars/expand-region.el

(use-package expand-region)
(require 'expand-region)
(global-set-key (kbd "C-=") 'er/expand-region)
;; Use-package

(use-package flycheck
  :hook
  (org-src-mode . my-org-mode-flycheck-hook)
  :config
  (defun my-org-mode-flycheck-hook ()
    (when (derived-mode-p 'prog-mode) ;; Check if it's a programming mode
      (flycheck-mode 1))))
;; Helm
;; - [[id:96c0f509-c06b-4e48-8f28-019cd2ca1a38][Helm reference header]]

(use-package helm
  :config
  (global-set-key (kbd "C-x b") 'helm-mini)
  (global-set-key (kbd "C-s") 'helm-occur)
  (setq
   helm-completion-style 'emacs
   helm-move-to-line-cycle-in-source nil)) ;; allow C-n through different sections
;; helm-org

(use-package helm-org
  :config
  (global-set-key (kbd "C-c j") 'helm-org-in-buffer-headings)
  (global-set-key (kbd "C-c w") 'helm-org-refile-locations)
  (setq org-outline-path-complete-in-steps 1
	org-refile-allow-creating-parent-nodes 'confirm
	org-refile-targets '((org-agenda-files :maxlevel . 20))
	org-refile-use-outline-path 'file))
  (define-key global-map (kbd "C-c C-j") nil)
  (global-set-key (kbd "C-c C-j") 'helm-org-agenda-files-headings)
  (define-key global-map (kbd "C-$") 'org-mark-ring-goto)
  (global-set-key (kbd "C-c C-j") 'helm-org-agenda-files-headings)
  (setq helm-org-ignore-autosaves t)
  ;; The default (helm) completion style is case-sensitive even with
  ;; helm-case-fold-search 'smart.  Use basic+substring instead.
  (setq helm-org-completion-styles '(basic substring))
(global-set-key (kbd "C-c C-j") 'helm-org-agenda-files-headings)

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-j") 'helm-org-agenda-files-headings))
;;;; Yiming Chen–style org-refile workflow

;; 1) Targets = all currently opened .org buffers
(defun +org/opened-buffer-files ()
  "Return a list of opened .org files."
  (delq nil
        (mapcar (lambda (b)
                  (let ((f (buffer-file-name b)))
                    (when (and f (string-match-p "\\.org\\'" f)) f)))
                (buffer-list))))

(setq org-refile-targets '((+org/opened-buffer-files :maxlevel . 9)))

;; 2) Use outline path; make it Helm/Ivy friendly (single-step completion)
(setq org-refile-use-outline-path 'file)
(setq org-outline-path-complete-in-steps nil)
(setq org-refile-allow-creating-parent-nodes 'confirm)

;; 3) Cache (big speedup); refresh cache on idle
(setq org-refile-use-cache t)
(run-with-idle-timer
 300 t
 (lambda ()
   (org-refile-cache-clear)
   (ignore-errors (org-refile-get-targets))))

;; 4) “Search” mode: jump to a heading instead of moving current subtree
(defun +org-refile-jump ()
  "Use org-refile with C-u to jump to a heading."
  (interactive)
  (org-refile '(4)))

;; Suggested keys (optional)
;; C-c C-w is org’s default refile; bind jump to C-c j
(defun jg/helm-org-nohelm-filter (candidates)
  "Filter :nohelm: tagged headings and org-id link headings from helm-org."
  (cl-remove-if
   (lambda (cand)
     (let ((marker (get-text-property 0 'helm-realvalue cand)))
       (when (markerp marker)
         (with-current-buffer (marker-buffer marker)
           (save-excursion
             (goto-char marker)
             (or (member "nohelm" (org-get-local-tags))
                 (string-match-p "\\[\\[id:" (org-get-heading t t t t))))))))
   candidates))

(advice-add 'helm-org--get-candidates-in-file :filter-return
            'jg/helm-org-nohelm-filter)
;; helm-org-rifle

(use-package helm-org-rifle
    :config
    (setq helm-org-rifle-show-path nil
	  helm-org-rifle-show-full-contents nil)
    (require 'helm)
    (global-set-key (kbd "C-c C-j") 'helm-org-agenda-files-headings))
;; Use-pacakge

(use-package htmlize)
;; Use-package

(use-package ivy
  :diminish)
;; Use-package

(use-package jupyter
  :demand t
  :init
  ;; jupyter lives in the basecamp conda env — add to exec-path so
  ;; ob-jupyter can find the binary at init time.
  ;; Preferred over system jupyter: avoids version conflicts with conda,
  ;; preserves env isolation. See [[file:~/repos/basecamp/basecamp.org][basecamp.org]] for jupyter/ipykernel install.
  (let ((jupyter-dir (expand-file-name "~/miniconda3/envs/basecamp/bin")))
    (unless (member jupyter-dir exec-path)
      (add-to-list 'exec-path jupyter-dir)
      (setenv "PATH" (concat jupyter-dir ":" (getenv "PATH")))))
  :config
  (require 'ob-jupyter)
  (org-babel-jupyter-aliases-from-kernelspecs))
;; key-chord

;;Exit insert mode by pressing j and then j quickly
;; https://stackoverflow.com/questions/10569165/how-to-map-jj-to-esc-in-emacs-evil-mode
(use-package key-chord)
(key-chord-mode 1)
;(use-package key-chord
;  :ensure t)
(key-chord-mode 1)
(setq key-chord-two-keys-delay 0.01)
;;(key-chord-define evil-insert-state-map "jj" 'evil-normal-state)

;; - [[https://github.com/emacsorphanage/key-chord][repo]]

(key-chord-define-global ",." "<>\C-b")

;; <> <> ,.<sf>

(key-chord-define-global "jc"     'claude-code-ide-menu)
(key-chord-define-global "xx"      'shell)
(key-chord-define-global ",,"     'indent-for-comment)
(key-chord-define-global "vv"     'vterm)
(key-chord-define-global "jk" #'completion-at-point)   ; normal text buffers
(key-chord-define-global "xo" 'other-window)
(key-chord-define-global "x1" 'delete-other-windows)
(key-chord-define org-mode-map "cd" 'my-collapse-all-drawers)

(setq key-chord-typing-detection t)
;; Magit
;; https://www.reddit.com/r/emacs/comments/1mq2hww/why_do_i_find_magit_so_hard_to_use/

(use-package magit)
;; marginalia

(use-package marginalia
  ;; Either bind `marginalia-cycle' globally or only in the minibuffer
  :bind (("M-A" . marginalia-cycle)
         :map minibuffer-local-map
         ("M-A" . marginalia-cycle))
  ;; The :init configuration is always executed (Not lazy!)
  :init
  (marginalia-mode)
  :ensure t)
;; mark-whole-word

  ;; https://emacs.stackexchange.com/questions/35069/best-way-to-select-a-word
  (defun mark-whole-word (&optional arg allow-extend)
    "Like `mark-word', but selects whole words and skips over whitespace.
  If you use a negative prefix arg then select words backward.
  Otherwise select them forward.

  If cursor starts in the middle of word then select that whole word.

  If there is whitespace between the initial cursor position and the
  first word (in the selection direction), it is skipped (not selected).

  If the command is repeated or the mark is active, select the next NUM
  words, where NUM is the numeric prefix argument.  (Negative NUM
  selects backward.)"
    (interactive "P\np")
    (let ((num  (prefix-numeric-value arg)))
      (unless (eq last-command this-command)
	(if (natnump num)
	    (skip-syntax-forward "\\s-")
	  (skip-syntax-backward "\\s-")))
      (unless (or (eq last-command this-command)
		  (if (natnump num)
		      (looking-at "\\b")
		    (looking-back "\\b")))
	(if (natnump num)
	    (left-word)
	  (right-word)))
      (mark-word arg allow-extend)))

  (global-set-key (kbd "C-c C-SPC") 'mark-whole-word)
;; Use-package

(use-package native-complete)
;; ob-mermaid
;; Suppress zenuml/core stderr popup on every mermaid eval.

(defun my/ob-mermaid-suppress-zenuml (orig-fn body params)
  (let ((orig-eval (symbol-function 'org-babel-eval)))
    (cl-letf (((symbol-function 'org-babel-eval)
               (lambda (cmd &rest args)
                 (apply orig-eval
                        (concat cmd " 2>/dev/null") args))))
      (funcall orig-fn body params))))
(advice-add 'org-babel-execute:mermaid :around #'my/ob-mermaid-suppress-zenuml)
;; (advice-remove 'org-babel-execute:mermaid #'my/ob-mermaid-suppress-zenuml)
;; open-chatgtp-query-in-new-browser-window

;; - Make a ChatGPT query from emacs
;;   - https://chatgpt.com/c/d4f18f6b-2f09-4a69-93f1-8f8ab5b39cb0

(defun open-chatgpt-query-in-new-browser-window (query &optional use-gpt-4)
  "Send a QUERY to ChatGPT and open the result in a new browser window.
With a prefix argument USE-GPT-4, use GPT-4 instead of GPT-4-turbo."
  (interactive "sEnter your ChatGPT query: \nP")
  (let* ((model (if use-gpt-4 "gpt-4" "gpt-4-turbo"))
         (url (concat "https://chat.openai.com/?q=" (url-hexify-string query)
                      "&model=" model)))
    (start-process "brave-browser" nil "brave-browser" "--new-window" url)))

(global-set-key (kbd "C-c C-g") 'open-chatgpt-query-in-new-browser-window)
;; Use-package

(add-to-list 'load-path "/usr/local/share/emacs/site-lisp/mu4e")

(use-package mu4e
  :ensure nil  ; installed via system package (maildir-utils)
  :commands mu4e
  :config
  ;; Core
  (setq mu4e-maildir "~/Mail"
        mu4e-get-mail-command "mbsync -a"
        mu4e-mu-binary "/usr/local/bin/mu"
        mu4e-update-interval 300
        mu4e-index-update-in-background t)

  ;; Identity
  (setq user-full-name "Jeff Szymanski"
        user-mail-address "jeszyman@gmail.com"
        mu4e-compose-reply-to-address "jeszyman@gmail.com")

  ;; Gmail folders
  (setq mu4e-sent-folder   "/gmail/[Gmail]/Sent Mail"
        mu4e-drafts-folder "/gmail/[Gmail]/Drafts"
        mu4e-trash-folder  "/gmail/[Gmail]/Trash"
        mu4e-refile-folder "/gmail/[Gmail]/All Mail")

  ;; Gmail handles sent via IMAP — don't duplicate
  (setq mu4e-sent-messages-behavior 'delete)

  ;; Maildir shortcuts
  (setq mu4e-maildir-shortcuts
        '((:maildir "/gmail/INBOX"             :key ?i)
          (:maildir "/gmail/mayo"              :key ?m)
          (:maildir "/gmail/[Gmail]/Sent Mail" :key ?s)
          (:maildir "/gmail/[Gmail]/Trash"     :key ?t)))

  ;; Send via msmtp
  (setq sendmail-program "/usr/bin/msmtp"
        send-mail-function 'sendmail-send-it
        message-send-mail-function 'sendmail-send-it
        message-sendmail-f-is-evil t
        message-sendmail-extra-arguments '("--read-envelope-from"))

  ;; UI
  (setq mu4e-view-show-images t
        mu4e-view-show-addresses t
        mu4e-headers-date-format "%Y-%m-%d"
        mu4e-use-fancy-chars t)

  ;; Threading
  (setq mu4e-headers-threading t
        mu4e-headers-thread-folding t
        mu4e-headers-include-related t)

  ;; Org integration
  (require 'org-mu4e))
;; Thread folding keybindings

(with-eval-after-load 'mu4e
  (define-key mu4e-headers-mode-map (kbd "z a") #'mu4e-thread-fold-all)
  (define-key mu4e-headers-mode-map (kbd "z n") #'mu4e-thread-unfold-all)
  (define-key mu4e-headers-mode-map (kbd "z t") #'mu4e-thread-fold-toggle))
;; Immediate refile (archive)

(with-eval-after-load 'mu4e
  (defun jg/mu4e-refile-now ()
    "Refile message at point immediately."
    (interactive)
    (mu4e-headers-mark-for-refile)
    (mu4e-mark-execute-all 'no-confirmation)
    (delete-other-windows))

  (defun jg/mu4e-refile-thread-now ()
    "Refile entire thread at point immediately."
    (interactive)
    (mu4e-headers-mark-thread-using-markpair '(refile) t)
    (mu4e-mark-execute-all 'no-confirmation)
    (delete-other-windows))

  (define-key mu4e-headers-mode-map (kbd "r") #'jg/mu4e-refile-now)
  (define-key mu4e-headers-mode-map (kbd "T") #'jg/mu4e-refile-thread-now))
;; Org thread link storage

(with-eval-after-load 'mu4e
  (defun jg/mu4e-org-store-thread-link ()
    "Store an org link to the mu4e thread at point using msgid query."
    (when (and (derived-mode-p 'mu4e-headers-mode 'mu4e-view-mode)
               (mu4e-message-at-point t))
      (let* ((msg (mu4e-message-at-point))
             (msgid (mu4e-message-field msg :message-id))
             (refs (mu4e-message-field msg :references))
             (oldest-id (if refs (car refs) msgid))
             (subject (mu4e-message-field msg :subject))
             (clean-subject (replace-regexp-in-string "^\\(Re\\|Fw\\|Fwd\\): *" "" subject t))
             (link (concat "mu4e:query:msgid:" oldest-id))
             (desc (concat clean-subject " thread")))
        (org-link-store-props :type "mu4e" :link link :description desc)
        link)))
  (org-link-set-parameters "mu4e" :store #'jg/mu4e-org-store-thread-link))
;; Display buffer rules

(with-eval-after-load 'mu4e
  (add-to-list 'display-buffer-alist
               '("\\*mu4e-headers\\*" (display-buffer-pop-up-frame))))
;; Silence minibuffer tips

(with-eval-after-load 'mu4e
  (advice-add 'mu4e~main-tip :override #'ignore))
;; Transient

(with-eval-after-load 'mu4e
  (transient-define-prefix jg/mu4e-transient ()
    "mu4e actions"
    [["Message"
      ("R" "Reply" mu4e-compose-reply)
      ("F" "Forward" mu4e-compose-forward)
      ("C" "Compose new" mu4e-compose-new)]
     ["Archive"
      ("r" "Archive message" jg/mu4e-refile-now)
      ("T" "Archive thread" jg/mu4e-refile-thread-now)]
     ["Mark"
      ("d" "Trash" mu4e-headers-mark-for-trash)
      ("D" "Delete" mu4e-headers-mark-for-delete)
      ("!" "Flag" mu4e-headers-mark-for-flag)
      ("x" "Execute marks" mu4e-mark-execute-all)]
     ["Thread"
      ("z a" "Fold all" mu4e-thread-fold-all)
      ("z n" "Unfold all" mu4e-thread-unfold-all)
      ("z t" "Toggle fold" mu4e-thread-fold-toggle)]
     ["Navigate"
      ("s" "Search" mu4e-headers-search)
      ("g" "Refresh" mu4e-headers-rerun-search)
      ("j" "Jump to maildir" mu4e~headers-jump-to-maildir)
      ("l" "Store org link" org-store-link)]])
  (define-key mu4e-headers-mode-map (kbd "?") #'jg/mu4e-transient))
;; Use-package

(use-package openwith
  :config
  (setq openwith-associations
        '(("\\.\\(pdf\\|docx\\|xlsx\\|pptx\\|svg\\|png\\|jpg\\|mp4\\)\\'" "xdg-open" (file))))
  (openwith-mode t))
;; orderless

(use-package orderless
  :init
  ;; Configure a custom style dispatcher (see the Consult wiki)
  ;; (setq orderless-style-dispatchers '(+orderless-dispatch)
  ;;       orderless-component-separator #'orderless-escapable-split-on-space)
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))
;; org-edna

(use-package org-edna
  :ensure t
  :config
  (org-edna-mode 1))
;; org-include-inline
;; [[https://github.com/yibie/org-include-inline][github: yibie/org-include-inline]]
;; - UUID-based includes work; CUSTOM_ID does not; export from UUID breaks
;; - Enable per buffer: ~M-x org-include-inline-mode~

;; Load only — enable per buffer with M-x org-include-inline-mode
(use-package org-include-inline
  :vc (:url "https://github.com/yibie/org-include-inline" :vc-backend Git))
;; Use-package

(use-package org-contrib
  :ensure t)
(require 'org-checklist)
(require 'ox-extra)
(ox-extras-activate '(ignore-headlines))
;; org-ql
;; - org-ql to pull time logs as tabular data exports [[https://claude.ai/chat/c4df90a0-faa0-459e-99a5-cd8d8e3945a6]]

(use-package org-ql)
;; org-ros
;; https://github.com/LionyxML/ros
;; https://chatgpt.com/c/6841f0e8-c080-8005-a3ed-fc6d67a76e19

(with-eval-after-load 'org-ros
  (defun org-ros ()
    "Screenshots an image to an org-file, prompting for filename with path completion."
    (interactive)
    (if buffer-file-name
        (progn
          (message "Waiting for region selection with mouse...")
          (let* ((default-filename (concat
                                     (file-name-nondirectory buffer-file-name)
                                     "_"
                                     (format-time-string "%Y%m%d_%H%M%S")
                                     ".png"))
                 (filepath (read-file-name
                            "Save screenshot as: "
                            (file-name-directory buffer-file-name)
                            nil nil
                            default-filename)))
            ;; ensure .png extension
            (unless (string-suffix-p ".png" filepath)
              (setq filepath (concat filepath ".png")))
            ;; ensure parent directory exists
            (make-directory (file-name-directory filepath) t)
            ;; capture screenshot
            (cond ((executable-find org-ros-primary-screencapture)
                   (call-process org-ros-primary-screencapture nil nil nil org-ros-primary-screencapture-switch filepath))
                  ((executable-find org-ros-secondary-screencapture)
                   (call-process org-ros-secondary-screencapture nil nil nil org-ros-secondary-screencapture-switch filepath))
                  ((executable-find org-ros-windows-screencapture)
                   (start-process "powershell" "*PowerShell*" "powershell.exe"
                                  "-File" (expand-file-name "./printsc.ps1" org-ros-dir) filepath)))
            ;; insert Org link
            (insert (format "[[file:%s][%s]]" filepath (file-name-nondirectory filepath)))
            (org-display-inline-images t t))
          (message "File created and linked..."))
      (message "You're in a not saved buffer! Save it first!"))))
;; ox-pandoc

(use-package ox-pandoc
  :after org
  :config
  (setq org-pandoc-options-for-docx '((standalone . nil)))
  )
;; Python

;; Use-package

(use-package savehist)
;; snakemake-mode

(use-package snakemake-mode)
(defcustom snakemake-indent-field-offset nil
  "Offset for field indentation."
  :type 'integer)

(defcustom snakemake-indent-value-offset nil
  "Offset for field values that the line below the field key."
  :type 'integer)
;; Tree-sitter

;; Install and configure tree-sitter
(use-package tree-sitter
  :ensure t
	 )

;; Install and configure tree-sitter-langs
(use-package tree-sitter-langs
  :ensure t
  :after tree-sitter
  :config
  (add-hook 'tree-sitter-after-on-hook #'tree-sitter-hl-mode))

(global-tree-sitter-mode)
(add-hook 'tree-sitter-after-on-hook #'tree-sitter-hl-mode)

(defun disable-tree-sitter-for-org-mode ()
  (when (eq major-mode 'org-mode)
    (tree-sitter-mode -1)))

(add-hook 'tree-sitter-mode-hook #'disable-tree-sitter-for-org-mode)
;; Use `consult-completion-in-region' if Vertico is enabled.

;; Otherwise use the default `completion--in-region' function.
(setq completion-in-region-function
      (lambda (&rest args)
        (apply (if vertico-mode
                   #'consult-completion-in-region
                 #'completion--in-region)
               args)))
;; other

;; Ensure you have these packages installed
(use-package vertico
  :ensure t
  :config
  (vertico-mode)
  ;; Performance improvements
  (setq vertico-count 10)
  (setq vertico-cycle nil)
  (setq vertico-preselect 'first))

;; Only show relevant commands in M-x
(setq read-extended-command-predicate
      #'command-completion-default-include-p)

;; Optimize orderless for better performance
(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion))))
  :config
  ;; Use faster matching styles
  (setq orderless-matching-styles '(orderless-literal orderless-regexp)))
(use-package marginalia
  :ensure t
  :after vertico
  :init
  (marginalia-mode))

(use-package savehist
  :ensure t
  :init
  (savehist-mode))

(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ("C-s" . consult-line)
         ("M-g g" . consult-goto-line)
         ("M-g M-g" . consult-goto-line)
         ("C-M-l" . consult-imenu)
         :map minibuffer-local-map
         ("M-r" . consult-history))
  :init
  (setq register-preview-delay 0
        register-preview-function #'consult-register-preview)
  ;; Optionally configure preview
  (autoload 'consult-register-window "consult")
  (setq consult-register-window-function #'consult-register-window)
  ;; Optionally configure narrowing key
  (setq consult-narrow-key "<"))

;; Enable vertico-directory for better directory navigation
(use-package vertico-directory
  :ensure nil
  :load-path "path/to/vertico-directory"
  :after vertico
  :bind (:map vertico-map
              ("RET" . vertico-directory-enter)
              ("DEL" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word)))

;; Example configuration for more intuitive completion cycling
(define-key vertico-map (kbd "TAB") #'minibuffer-complete)
(define-key vertico-map (kbd "C-n") #'vertico-next)
(define-key vertico-map (kbd "C-p") #'vertico-previous)
;; vterm
;; - exit nano w/ Esc Esc X [[https://stackoverflow.com/questions/66771206/how-do-i-exit-nano-in-emacs-26-3][SO: exit nano in emacs]]
;; - [[https://www.reddit.com/r/emacs/comments/op4fcm/send_command_to_vterm_and_execute_it/][Reddit: send command to vterm]]

;; CUA registers in emulation-mode-map-alists (higher priority than
;; minor-mode-overriding-map-alist), so we override at the same level.
(defvar my/vterm-keys-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-v") #'vterm-yank)
    (define-key map (kbd "C-z") #'vterm-undo)
    map))

(define-minor-mode my/vterm-override-mode
  "Override CUA keys in vterm."
  :keymap my/vterm-keys-map)

;; push (not add-to-list) so our entry lands BEFORE cua--keymap-alist,
;; which CUA adds early — otherwise CUA's C-v binding wins.
(push `((my/vterm-override-mode . ,my/vterm-keys-map))
      emulation-mode-map-alists)

(defun my/vterm-insert-file-path ()
  "Insert a file path into vterm using Emacs completion."
  (interactive)
  (let ((path (read-file-name "Path: ")))
    (vterm-insert path)))

(use-package vterm
  :init
  (add-hook 'vterm-mode-hook #'my/vterm-override-mode)
  :config
  (setq vterm-max-scrollback 100000)
  ;; S-TAB: Emacs path completion in vterm (useful for claude-code-ide prompts)
  (define-key vterm-mode-map [backtab] #'my/vterm-insert-file-path)
  (custom-set-faces
   '(vterm-color-blue ((t (:foreground "#477EFC" :background "#477EFC"))))))
;; Use-package

(use-package web-mode
  :mode ("\\.phtml\\'"
         "\\.tpl\\.php\\'"
         "\\.[agj]sp\\'"
         "\\.as[cp]x\\'"
         "\\.erb\\'"
         "\\.mustache\\'"
         "\\.djhtml\\'"
         "\\.html?\\'"))
;; Use-package

(use-package whisper
  :load-path "~/.emacs.d/lisp/whisper"
  :config
  (setq whisper-install-directory "~/.emacs.d/.cache/whisper.cpp/"
        whisper-model "base"
        whisper-language "en"
        whisper-translate nil
        whisper-use-threads (/ (num-processors) 2)
        ;; Newer whisper.cpp sends transcription to stderr with --print-progress
        whisper-show-progress-in-mode-line nil)
  ;; Machine-specific mic: Logitech Webcam C925e on jeff-beast
  (when (string= (system-name) "jeff-beast")
    (setq whisper--ffmpeg-input-device
          "alsa_input.usb-046d_Logitech_Webcam_C925e_9891F59F-02.analog-stereo"))
  ;; Remove read-only guard so whisper works in vterm
  (setq whisper-before-transcription-hook nil)
  ;; Track vterm origin for direct text insertion
  (defvar my/whisper--vterm-target nil)
  ;; When non-nil, skip vterm-send-return after transcription (WW chord)
  (defvar my/whisper--no-return nil)
  ;; In vterm: send transcription via vterm-send-string, clear stdout buffer
  ;; so whisper skips creating a display buffer
  (add-hook 'whisper-after-transcription-hook
            (lambda ()
              (when my/whisper--vterm-target
                (let ((text (buffer-substring-no-properties (point-min) (point-max))))
                  (with-current-buffer my/whisper--vterm-target
                    (vterm-send-string text)
                    (unless my/whisper--no-return
                      (vterm-send-return))))
                (erase-buffer))))
  ;; Restore state after each run
  (add-hook 'whisper-after-insert-hook
            (lambda ()
              (setq whisper-insert-text-at-point t
                    my/whisper--vterm-target nil
                    my/whisper--no-return nil)))
  ;; ffmpeg 4.4 drops audio on signals; send "q" to stdin for clean shutdown.
  ;; In vterm, disable insert-at-point so vterm hook handles it instead.
  (advice-add 'whisper-run :around
              (lambda (orig-fn &optional arg)
                (if (process-live-p whisper--recording-process)
                    (process-send-string whisper--recording-process "q")
                  (when (derived-mode-p 'vterm-mode)
                    (setq my/whisper--vterm-target (current-buffer)
                          whisper-insert-text-at-point nil))
                  (funcall orig-fn arg)))
              '((name . my/whisper-quit-for-ffmpeg)))
  (defun my/whisper-run-with-mic ()
    "Boost mic to 100% before invoking whisper-run."
    (interactive)
    (let ((source (if (string= (system-name) "jeff-beast")
                      "alsa_input.usb-046d_Logitech_Webcam_C925e_9891F59F-02.analog-stereo"
                    (string-trim (shell-command-to-string "pactl get-default-source")))))
      (call-process "pactl" nil nil nil "set-source-volume" source "65536"))
    (whisper-run))
  (defun my/whisper-run-with-mic-no-return ()
    "Stop whisper recording without sending return in vterm."
    (interactive)
    (setq my/whisper--no-return t)
    (if (process-live-p whisper--recording-process)
        (process-send-string whisper--recording-process "q")
      (my/whisper-run-with-mic)))
  (key-chord-define-global "ww" 'my/whisper-run-with-mic)
  (key-chord-define-global "WW" 'my/whisper-run-with-mic-no-return))
;; yaml

(use-package yaml-mode)
;; Use-package

(use-package yasnippet
  :init
  ;; Ensure the snippets directory exists
  (let ((snippets-dir "~/.emacs.d/snippets"))
    (unless (file-directory-p snippets-dir)
      (make-directory snippets-dir t)))

  ;; Dynamically add subdirectories in ~/.emacs.d/snippets to yas-snippet-dirs
  (setq yas-snippet-dirs
        (directory-files "~/.emacs.d/snippets" t "^[^.]+")) ; Directories only
  :config
  (yas-global-mode 1) ; Enable yasnippet globally
  (define-key yas-minor-mode-map (kbd "<C-tab>") 'yas-expand))
;; (use-package yasnippet
;;   :init
;;   ;; Dynamically add subdirectories in ~/.emacs.d/snippets to yas-snippet-dirs
;;   (setq yas-snippet-dirs
;;         (directory-files "~/.emacs.d/snippets" t "^[^.]+")) ; Directories only, no append needed
;;    :config
;;   (yas-global-mode 1) ; Enable yasnippet globally
;;   (define-key yas-minor-mode-map (kbd "<C-tab>") 'yas-expand))
(defun my-org-mode-hook ()
  (setq-local yas-buffer-local-condition
              '(not (org-in-src-block-p t))))
(add-hook 'org-mode-hook #'my-org-mode-hook)
;; Prevent company mode during expansions

(add-hook 'yas-before-expand-snippet-hook (lambda () (setq-local company-backends nil)))
(add-hook 'yas-after-exit-snippet-hook    (lambda () (kill-local-variable 'company-backends)))
;; Provide a setting to auto-expand snippets

(setq require-final-newline nil)
(defun yas-auto-expand ()
  "Function to allow automatic expansion of snippets which contain a condition, auto."

  (when yas-minor-mode
    (let ((yas-buffer-local-condition ''(require-snippet-condition . auto)))
      (yas-expand))))

(defun my-yas-try-expanding-auto-snippets ()
  (when yas-minor-mode
    (let ((yas-buffer-local-condition ''(require-snippet-condition . auto)))
      (yas-expand))))

(add-hook 'post-command-hook #'my-yas-try-expanding-auto-snippets)
;; org-repeat-by-cron

(use-package org-repeat-by-cron
  :ensure t  ; If the file is already in your load-path
  :config
  (global-org-repeat-by-cron-mode))
;; Use-package                                                    :nohelm:

(use-package claude-code-ide
  :vc (:url "https://github.com/manzaltu/claude-code-ide.el" :rev :newest)
  :demand t
  :config
  (claude-code-ide-emacs-tools-setup)
  ;; Switch to claude buffer in the current window
  (add-to-list 'display-buffer-alist
               '("\\*claude-code\\["
                 (display-buffer-same-window))))
(setq claude-code-ide-use-side-window nil)
(setq claude-code-ide-use-ide-diff nil)
(setq claude-code-ide-cli-extra-flags "--dangerously-skip-permissions")
;; Ediff workarounds                                              :nohelm:

;; # Problem: claude-code-ide diff overrides the claude window in i3.
;; # Root cause: claude-code-ide hardcodes ediff-window-setup-function to
;; # 'ediff-setup-windows-plain via setq immediately before calling ediff-buffers,
;; # so global setq has no effect.
;; # Fix: :before advice on ediff-buffers runs after claude-code-ide's setq but
;; # before ediff reads it.

(advice-add 'ediff-buffers :before
            (lambda (&rest _)
              (setq ediff-window-setup-function 'ediff-setup-windows-multiframe)))
;; Org-mode navigation MCP tools                                  :nohelm:

;; MCP tools use deferred (lazy) loading in Claude Code — they appear as
;; "available deferred tools" at session start and are fetched on first use via
;; =ToolSearch=. Warnings about unavailable MCP tools on startup are expected
;; and do not indicate a failure.

;; Four tools that give Claude structural org-mode navigation — outline first,
;; then drill to a subtree by ID or heading name, or query across files with
;; org-ql. Much more token-efficient than reading whole files.

;; These tools run as elisp inside the live Emacs session via [[https://github.com/stevemolitor/claude-code-ide.el][claude-code-ide.el]]: Claude Code sends JSON-RPC requests over a socket, which dispatch to functions like =claude-code-ide-org-outline= that call native org-mode APIs (=org-map-entries=, =org-id-find=, etc.) directly. This means they operate with full org-mode context — no subprocess overhead, no parsing from scratch.

(defun claude-code-ide-org-outline (file-path &optional depth)
  "Return heading-only outline of FILE-PATH up to DEPTH levels."
  (claude-code-ide-mcp-server-with-session-context nil
    (let ((max-depth (or depth 3)))
      (with-current-buffer (find-file-noselect file-path)
        (let (headings)
          (org-map-entries
           (lambda ()
             (when (<= (org-current-level) max-depth)
               (push (concat (make-string (org-current-level) ?*)
                             " "
                             (substring-no-properties (org-get-heading t t t t)))
                     headings))))
          (string-join (nreverse headings) "\n"))))))
(defun claude-code-ide-org-subtree-by-id (org-id)
  "Return full subtree content for heading with ORG-ID."
  (claude-code-ide-mcp-server-with-session-context nil
    (require 'org-id)
    (let ((marker (org-id-find org-id 'marker)))
      (if marker
          (with-current-buffer (marker-buffer marker)
            (goto-char marker)
            (substring-no-properties
             (buffer-substring (point)
                               (save-excursion (org-end-of-subtree t) (point)))))
        (format "No heading found with id: %s" org-id)))))
(defun claude-code-ide-org-subtree-by-heading (file-path heading)
  "Return subtree content for first heading matching HEADING in FILE-PATH."
  (claude-code-ide-mcp-server-with-session-context nil
    (with-current-buffer (find-file-noselect file-path)
      (goto-char (point-min))
      (if (re-search-forward (format "^\\*+ %s" (regexp-quote heading)) nil t)
          (progn
            (beginning-of-line)
            (substring-no-properties
             (buffer-substring (point)
                               (save-excursion (org-end-of-subtree t) (point)))))
        (format "No heading matching '%s' found in %s" heading file-path)))))
(defun claude-code-ide-org-ql-query (files query &optional include-file)
  "Run org-ql QUERY across FILES (space-separated paths).
Returns matching heading titles with org-id when present, optionally prefixed with filename."
  (claude-code-ide-mcp-server-with-session-context nil
    (require 'org-ql)
    (let* ((file-list (split-string files " " t))
           (show-file (if (null include-file) t include-file))
           (parsed-query (car (read-from-string query))))
      (mapcar
       (lambda (e)
         (let* ((h (org-element-property :raw-value e))
                (marker (org-element-property :org-hd-marker e))
                (f (buffer-file-name (marker-buffer marker)))
                (id (with-current-buffer (marker-buffer marker)
                      (goto-char marker)
                      (org-entry-get (point) "ID")))
                (id-str (if id (concat " [id:" id "]") ""))
                (file-str (if show-file (concat (file-name-nondirectory f) ": ") "")))
           (concat file-str h id-str)))
       (org-ql-select file-list parsed-query
         :action 'element-with-markers)))))
(defun claude-code-ide-org-refile-subtree (file-path source-heading target-heading &optional as-sibling source-id target-id)
  "Move subtree SOURCE-HEADING relative to TARGET-HEADING in FILE-PATH.
By default pastes as the last child of target. With AS-SIBLING non-nil,
pastes after the target subtree at the same level instead.
SOURCE-ID and TARGET-ID are optional org-id UUIDs for disambiguation.
When provided, the heading is located by ID instead of text search.
If text search finds multiple matches and no ID is provided, errors
with a list of matches (line numbers and levels) for disambiguation.
Saves the buffer on success."
  (claude-code-ide-mcp-server-with-session-context nil
    (with-current-buffer (find-file-noselect file-path)
      (org-with-wide-buffer
       (let* ((case-fold-search nil)
              (heading-re (lambda (h) (format "^\\*+ %s\\([ \t]\\|$\\)" (regexp-quote h))))
              (find-by-id (lambda (id)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   (format "^[ \t]*:ID:[ \t]+%s" (regexp-quote id)) nil t)
                              (org-back-to-heading t)
                              (point))))
              (find-unique (lambda (heading id label)
                             (if id
                                 (or (funcall find-by-id id)
                                     (error "%s ID '%s' not found" label id))
                               (goto-char (point-min))
                               (let ((positions nil))
                                 (while (re-search-forward (funcall heading-re heading) nil t)
                                   (save-excursion
                                     (beginning-of-line)
                                     (push (list (line-number-at-pos)
                                                 (org-current-level)
                                                 (org-get-heading t t t t))
                                           positions)))
                                 (setq positions (nreverse positions))
                                 (cond
                                  ((null positions)
                                   (error "%s heading '%s' not found" label heading))
                                  ((= 1 (length positions))
                                   (goto-char (point-min))
                                   (re-search-forward (funcall heading-re heading) nil t)
                                   (beginning-of-line)
                                   (point))
                                  (t
                                   (error "%s heading '%s' is ambiguous (%d matches). Provide an ID to disambiguate. Matches: %s"
                                          label heading (length positions)
                                          (mapconcat (lambda (p)
                                                       (format "L%d (level %d: %s)"
                                                               (nth 0 p) (nth 1 p) (nth 2 p)))
                                                     positions ", "))))))))
         (let ((src-pos (funcall find-unique source-heading source-id "Source"))
               (tgt-pos (funcall find-unique target-heading target-id "Target")))
           (goto-char src-pos)
           (org-cut-subtree)
           ;; Re-find target after cut (positions shifted)
           (let ((tgt-pos2 (if target-id
                               (funcall find-by-id target-id)
                             (progn (goto-char (point-min))
                                    (re-search-forward (funcall heading-re target-heading) nil t)
                                    (beginning-of-line)
                                    (point)))))
             (goto-char tgt-pos2)
             (let ((target-level (org-current-level)))
               (org-end-of-subtree t)
               (unless (bolp) (newline))
               (if as-sibling
                   (org-paste-subtree target-level)
                 (org-paste-subtree (1+ target-level)))))
           (save-buffer)
           (format "Moved '%s' %s '%s'"
                   source-heading
                   (if as-sibling "after" "under")
                   target-heading))))))))
(with-eval-after-load 'claude-code-ide
  (claude-code-ide-make-tool
   :function #'claude-code-ide-org-outline
   :name "org_outline"
   :description "Get a heading-only outline of an org file at a given depth. Use this FIRST to orient before reading any subtree. Returns just the heading hierarchy, no body text — very token-efficient."
   :args '((:name "file_path"
                  :type string
                  :description "Absolute path to the org file")
           (:name "depth"
                  :type number
                  :description "Maximum heading depth to show (1-6, default 3)"
                  :optional t)))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-org-subtree-by-id
   :name "org_subtree_by_id"
   :description "Get the full content of an org subtree by its org-id UUID. Use after finding the ID from an outline or prior search."
   :args '((:name "org_id"
                  :type string
                  :description "The org-id UUID of the heading to retrieve")))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-org-subtree-by-heading
   :name "org_subtree_by_heading"
   :description "Get the full content of an org subtree by searching for a heading name. Returns content from the first matching heading."
   :args '((:name "file_path"
                  :type string
                  :description "Absolute path to the org file")
           (:name "heading"
                  :type string
                  :description "Heading text to search for (exact text, not regex)")))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-org-ql-query
   :name "org_ql_query"
   :description "Query org files using org-ql predicates. Returns matching heading titles with their file. Common predicates: (todo \"TODO\"), (tags \"tag\"), (heading \"text\"), (and ...), (or ...)."
   :args '((:name "files"
                  :type string
                  :description "Space-separated list of absolute org file paths to search")
           (:name "query"
                  :type string
                  :description "org-ql query string, e.g. \"(todo \\\"TODO\\\")\" or \"(and (tags \\\"focus\\\") (todo \\\"INPROCESS\\\"))\"")
           (:name "include_file"
                  :type boolean
                  :description "Prefix results with filename (default true)"
                  :optional t)))

  (claude-code-ide-make-tool
   :function #'claude-code-ide-org-refile-subtree
   :name "org_refile_subtree"
   :description "Move an org subtree (by exact heading title) relative to another heading in the same file. Default: paste as last child of target. With as_sibling=true: paste after target at same level. Errors on ambiguous heading names — provide source_id/target_id to disambiguate."
   :args '((:name "file_path"
                  :type string
                  :description "Absolute path to the org file")
           (:name "source_heading"
                  :type string
                  :description "Exact heading title of the subtree to move (no stars, no tags)")
           (:name "target_heading"
                  :type string
                  :description "Exact heading title of the destination parent or sibling reference")
           (:name "as_sibling"
                  :type boolean
                  :description "If true, paste after target at same level rather than as a child"
                  :optional t)
           (:name "source_id"
                  :type string
                  :description "Org-id UUID of the source heading, for disambiguation when multiple headings share the same title"
                  :optional t)
           (:name "target_id"
                  :type string
                  :description "Org-id UUID of the target heading, for disambiguation when multiple headings share the same title"
                  :optional t))))
