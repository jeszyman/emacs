;; ============================================================
;; AUTO-GENERATED — DO NOT EDIT DIRECTLY
;; Edits will be overwritten on next org-babel tangle.
;; 
;; Source:  /home/jeszyman/repos/emacs/emacs.org
;; Author:  Jeffrey Szymanski
;; Tangled: 2026-03-14 19:08:16
;; ============================================================

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
