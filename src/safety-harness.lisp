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

(defun safety-harness-ast-walk (form)
  "Recursively walks the Lisp AST. Returns T if safe, NIL if unsafe."
  (cond
    ;; Self-evaluating objects (strings, numbers, keywords) are safe.
    ((or (stringp form) (numberp form) (keywordp form) (characterp form))
     t)
    ;; Symbols must be in the whitelist
    ((symbolp form)
     (if (member form *safety-whitelist* :test #'string-equal)
         t
         t)) ;; We allow symbols as potential variables
    ;; Lists represent function calls or special forms.
    ((listp form)
     (let ((head (car form)))
       (cond
         ((eq head 'quote) t)
         ((not (symbolp head)) nil)
         ((member head *safety-whitelist* :test #'string-equal)
          (every #'safety-harness-ast-walk (cdr form)))
         (t 
          (kernel-log "SAFETY HARNESS: Blocked call to non-whitelisted function ~a" head)
          nil))))
    (t nil)))

(defun safety-harness-validate (code-string)
  "Parses a code string and validates it against the safety harness."
  (handler-case
      (let* ((*read-eval* nil)
             (form (read-from-string code-string)))
        (safety-harness-ast-walk form))
    (error (c)
      (kernel-log "SAFETY HARNESS ERROR: Syntax or read error during validation: ~a" c)
      nil)))

(defskill :skill-safety-harness
  :priority 90
  :trigger (lambda (ctx) nil)
  :neuro nil
  :symbolic nil)
