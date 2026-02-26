;;-*- mode: elisp -*-

;; Package Management Setup

(require 'package)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)

;; Ensure 'use-package' is installed
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; Function to safely load a file if it exists
(defun safe-load-file-if-exists (filepath)
  "Safely load the Emacs Lisp file at FILEPATH if it exists.
If FILEPATH is relative, treat it as relative to `user-emacs-directory`."
  (let* ((file (if (file-name-absolute-p filepath)
                   filepath
                 (expand-file-name filepath user-emacs-directory))))
    (when (file-exists-p file)
      (condition-case err
          (load (file-name-sans-extension file))
        (error (message "Error loading %s: %s" file err))))))

;; Load early configuration
(safe-load-file-if-exists "load-first.el")

;; Define the path to your configuration directory
(defvar my-config-dir (expand-file-name "config/" user-emacs-directory)
  "Directory containing personal Emacs configuration files.")

;; Load all .el files in the config directory
(when (file-directory-p my-config-dir)
  (dolist (file (directory-files my-config-dir t "\\.el\\'"))
    (condition-case err
        (load (file-name-sans-extension file))
      (error (message "Error loading %s: %s" file err)))))

;; Define the path to your configuration directory
(defvar my-lisp-dir (expand-file-name "lisp/" user-emacs-directory)
  "Directory containing personal Emacs configuration files.")


;; If my-lisp-dir exists on disk, load every *.el file in it.
;; This is a "bulk loader" pattern: it eagerly loads everything at startup.
(when (file-directory-p my-lisp-dir)

  ;; Iterate over all files in my-lisp-dir whose names end in ".el".
  ;; - `t` means return absolute paths.
  ;; - "\\.el\\'" matches ".el" at end-of-string.
  (dolist (file (directory-files my-lisp-dir t "\\.el\\'"))

    ;; Try to load each file; if any file errors, catch it and continue.
    (condition-case err
        ;; `load` expects a library name, not necessarily a filename.
        ;; Using (file-name-sans-extension file) strips ".el" so `load`
        ;; will also find a corresponding ".elc" if present.
        ;;
        ;; 2nd arg NIL means: don't error if not found (still errors
        ;; on evaluation problems inside the file).
        ;; 3rd arg 'nomessage suppresses "Loading ..." chatter in *Messages*.
        (load (file-name-sans-extension file) nil 'nomessage)

      ;; If evaluation of that file signals an error, log it but keep going.
      (error (message "Error loading %s: %s" file err)))))


;; Load late configuration
(safe-load-file-if-exists "load-last.el")
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ess-R-font-lock-keywords
   '((ess-R-fl-keyword:modifiers . t) (ess-R-fl-keyword:fun-defs . t)
     (ess-R-fl-keyword:keywords . t) (ess-R-fl-keyword:assign-ops . t)
     (ess-R-fl-keyword:constants . t) (ess-fl-keyword:fun-calls . t)
     (ess-fl-keyword:numbers . t) (ess-fl-keyword:operators . t)
     (ess-fl-keyword:delimiters . t) (ess-fl-keyword:= . t)
     (ess-R-fl-keyword:F&T . t) (ess-R-fl-keyword:%op% . t)))
 '(package-selected-packages
   '(anki-editor auctex blacken casual citar-embark claude-code-ide conda
		 corfu elpy embark-consult ess esup
		 exec-path-from-shell expand-region flycheck-eglot
		 gptel helm-bibtex helm-org helm-org-rifle ivy-bibtex
		 jinx key-chord magit marginalia markdown-mode
		 mermaid-mode multi-vterm native-complete ob-async
		 ob-mermaid openwith orderless org-alert org-contrib
		 org-edna org-ql org-ref org-repeat-by-cron org-ros
		 pdf-tools rainbow-delimiters snakemake-mode
		 tree-sitter-langs vc-use-package vertico web-mode
		 yaml yaml-mode))
 '(safe-local-variable-values
   '((eval progn
	   (save-excursion
	     (org-babel-goto-named-src-block "setup-gastronomy")
	     (org-babel-execute-src-block))
	   (jg-recipes-sync-all))
     (eval add-hook 'after-save-hook
	   (lambda nil
	     (save-excursion
	       (goto-char (point-min))
	       (while
		   (re-search-forward "^#\\+name: grants-setup$" nil t)
		 (org-babel-execute-src-block))))
	   nil t)
     (eval save-excursion (goto-char (point-min))
	   (while (re-search-forward "^#\\+name: grants-setup$" nil t)
	     (org-babel-execute-src-block)))
     (eval org-babel-load-languages 'org-babel-load-languages
	   '((emacs-lisp . t)))
     (org-confirm-elisp-link-function))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "Hack" :height 114 :weight light)))))
(setq server-socket-dir (expand-file-name "server" user-emacs-directory))
(require 'server)
(unless (server-running-p) (server-start))
