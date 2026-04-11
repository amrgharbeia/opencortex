(in-package :org-agent)

(defparameter *safety-whitelist*
  '(;; Math & Logic
    + - * / = < > <= >= 1+ 1- min max
    and or not null eq eql equal string= string-equal
    ;; List Manipulation
    list cons car cdr cadr cddr cdar caar append mapcar remove-if remove-if-not
    length reverse sort nth nthcdr push pop
    ;; Plists and Hash Tables
    getf gethash
    ;; Control Flow
    let let* if cond when unless case typecase
    ;; Strings
    format concatenate string-downcase string-upcase search
    ;; Kernel specifics
    org-agent::kernel-log
    org-agent::snapshot-object-store
    org-agent::rollback-object-store
    org-agent::lookup-object
    org-agent::list-objects-by-type
    org-agent::ingest-ast
    org-agent::find-headline-missing-id
    org-agent::context-query-store
    org-agent::context-get-active-projects
    org-agent::context-get-recent-completed-tasks
    org-agent::context-list-all-skills
    org-agent::context-get-system-logs
    org-agent::context-assemble-global-awareness
    org-agent::org-object-id
    org-agent::org-object-type
    org-agent::org-object-attributes
    org-agent::org-object-content
    org-agent::org-object-parent-id
    org-agent::org-object-children
    org-agent::org-object-version
    org-agent::org-object-last-sync
    org-agent::org-object-hash
    ;; Essential macros
    declare ignore
    ;; Let's also add simple data types
    t nil quote function))

(defvar *safety-registry* nil
  "List of dynamically registered safe symbols.")

(defun safety-harness-register (symbols)
  "Adds symbols to the global safety registry."
  (setf *safety-registry* (append *safety-registry* (if (listp symbols) symbols (list symbols))))
  (kernel-log "SAFETY HARNESS: Registered ~a new safe symbols." (length (if (listp symbols) symbols (list symbols)))))

(defun safety-harness-is-safe (symbol)
  "Checks if a symbol is in the static whitelist or the dynamic registry."
  (or (member symbol *safety-whitelist* :test #'string-equal)
      (member symbol *safety-registry* :test #'string-equal)))

(defun safety-harness-ast-walk (form)
  "Recursively walks the Lisp AST. Returns T if safe, NIL if unsafe."
  (cond
    ;; Self-evaluating objects (strings, numbers, keywords) are safe.
    ((or (stringp form) (numberp form) (keywordp form) (characterp form))
     t)
    ;; Symbols used as variables (in non-function position)
    ((symbolp form)
     (safety-harness-is-safe form))
    ;; Lists represent function calls or special forms.
    ((listp form)
     (let ((head (car form)))
       (cond
         ((eq head 'quote) t)
         ((not (symbolp head)) nil)
         ((safety-harness-is-safe head)
          (every #'safety-harness-ast-walk (cdr form)))
         (t 
          (kernel-log "SAFETY HARNESS: Blocked call to non-whitelisted function ~a" head)
          nil))))
    (t nil)))

(defun safety-harness-validate (code)
  "Parses and validates a Lisp string or form."
  (let ((form (if (stringp code) (ignore-errors (read-from-string code)) code)))
    (if form
        (safety-harness-ast-walk form)
        nil)))
