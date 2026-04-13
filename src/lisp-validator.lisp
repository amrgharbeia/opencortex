(in-package :org-agent)

(defparameter *lisp-validator-whitelist*
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
    org-agent::harness-log
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

(defvar *lisp-validator-registry* nil
  "List of dynamically registered safe symbols.")

(defun lisp-validator-register (symbols)
  "Adds symbols to the global validator registry."
  (setf *lisp-validator-registry* (append *lisp-validator-registry* (if (listp symbols) symbols (list symbols))))
  (harness-log "LISP VALIDATOR: Registered ~a new safe symbols." (length (if (listp symbols) symbols (list symbols)))))

(defun lisp-validator-is-safe (symbol)
  "Checks if a symbol is in the static whitelist or the dynamic registry."
  (or (member symbol *lisp-validator-whitelist* :test #'string-equal)
      (member symbol *lisp-validator-registry* :test #'string-equal)))

(defun lisp-validator-ast-walk (form)
  "Recursively walks the Lisp AST. Returns T if safe, NIL if unsafe."
  (cond
    ;; Self-evaluating objects (strings, numbers, keywords) are safe.
    ((or (stringp form) (numberp form) (keywordp form) (characterp form))
     t)
    ;; Symbols used as variables (in non-function position)
    ((symbolp form)
     (lisp-validator-is-safe form))
    ;; Lists represent function calls or special forms.
    ((listp form)
     (let ((head (car form)))
       (cond
         ((eq head 'quote) t)
         ((not (symbolp head)) nil)
         ((lisp-validator-is-safe head)
          (every #'lisp-validator-ast-walk (cdr form)))
         (t 
          (harness-log "LISP VALIDATOR: Blocked call to non-whitelisted function ~a" head)
          nil))))
    (t nil)))

(org-agent:def-cognitive-tool :lisp-validator-status "Returns validator-related telemetry, including blocked actions and harness status."
  nil
  :body (lambda (args)
          (declare (ignore args))
          (format nil "LISP VALIDATOR STATUS:
- Static Whitelist: ~a symbols
- Dynamic Registry: ~a symbols
- Total Blocked Actions: ~a"
                  (length *lisp-validator-whitelist*)
                  (length *lisp-validator-registry*)
                  "Not implemented")))

(org-agent:defskill :skill-lisp-validator
  :priority 900 ; High priority, before most skills
  :trigger (lambda (ctx) 
             ;; Check if any proposed action is an :eval or :shell call
             (let ((candidate (getf ctx :candidate)))
               (when candidate
                 (let ((payload (getf candidate :payload)))
                   (member (getf payload :action) '(:eval :shell))))))
  :probabilistic nil ; Purely deterministic/safety skill
  :deterministic (lambda (action context)
              (harness-log "DETERMINISTIC ENGINE [Lisp-Validator]: Intercepted critical action for structural validation.")
              action))
