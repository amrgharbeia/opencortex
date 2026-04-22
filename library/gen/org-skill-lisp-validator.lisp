(in-package :opencortex)

(defun lisp-validator-check-structural (code-string)
  "Checks for balanced parens, brackets, and terminated strings.
Returns (VALUES t nil) if clean, or (VALUES nil reason-string line col)."
  (let ((stack nil)
        (in-string nil)
        (escaped nil)
        (line 1)
        (col 0)
        (last-open-line 1)
        (last-open-col 0))
    (dotimes (i (length code-string)
               (if (null stack)
                   (values t nil nil nil)
                   (values nil (format nil "Unbalanced '~a' opened at line ~a, col ~a"
                                       (caar stack) last-open-line last-open-col)
                           last-open-line last-open-col)))
      (let ((ch (char code-string i)))
        (cond (escaped (setf escaped nil))
              ((char= ch #\\) (setf escaped t))
              (in-string
               (when (char= ch #\") (setf in-string nil)))
              ((char= ch #\;)
               ;; Skip to end of line
               (loop while (and (< i (1- (length code-string)))
                                (not (char= (char code-string (1+ i)) #\Newline)))
                     do (incf i))
               (incf line) (setf col 0))
              ((char= ch #\")
               (setf in-string t))
              ((member ch '(#\( #\[))
               (push (list (string ch) line col) stack)
               (setf last-open-line line last-open-col col))
              ((char= ch #\))
               (cond ((null stack)
                      (return-from lisp-validator-check-structural
                        (values nil (format nil "Unexpected ')' at line ~a, col ~a" line col) line col)))
                     ((string= (caar stack) "[")
                      (return-from lisp-validator-check-structural
                        (values nil (format nil "Mismatched ']' expected at line ~a, col ~a" line col) line col)))
                     (t (pop stack))))
              ((char= ch #\])
               (cond ((null stack)
                      (return-from lisp-validator-check-structural
                        (values nil (format nil "Unexpected ']' at line ~a, col ~a" line col) line col)))
                     ((string= (caar stack) "(")
                      (return-from lisp-validator-check-structural
                        (values nil (format nil "Mismatched ')' expected at line ~a, col ~a" line col) line col)))
                     (t (pop stack))))
               ((char= ch #\Newline)
                (incf line) (setf col 0)))
          (unless (char= ch #\Newline) (incf col))))))

(defun lisp-validator-check-syntactic (code-string)
  "Checks if the code can be read by SBCL with *read-eval* nil.
Returns (VALUES t nil) if clean, or (VALUES nil error-message line col)."
  (handler-case
      (let ((*read-eval* nil))
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof) until (eq form :eof)))
        (values t nil nil nil))
    (error (c)
      (let ((msg (format nil "~a" c)))
        (values nil msg nil nil)))))

(defparameter *lisp-validator-whitelist*
  '(;; Math & Logic
    + - * / = < > <= >= 1+ 1- min max mod abs floor ceiling round
    and or not null eq eql equal string= string-equal char= char-equal
    ;; List Manipulation
    list cons car cdr cadr cddr cdar caar caddr cdddr append mapcar remove-if remove-if-not
    length reverse sort nth nthcdr push pop last butlast subseq
    ;; Plists, Alists, and Hash Tables
    getf gethash assoc acons pairlis rassoc
    ;; Control Flow
    let let* if cond when unless case typecase prog1 progn
    ;; Strings
    format concatenate string-downcase string-upcase search subseq replace
    ;; Type predicates
    stringp numberp integerp listp symbolp keywordp null
    ;; Kernel safe symbols
    opencortex::harness-log
    opencortex::snapshot-memory opencortex::rollback-memory
    opencortex::lookup-object opencortex::list-objects-by-type
    opencortex::ingest-ast opencortex::find-headline-missing-id
    opencortex::context-query-store opencortex::context-get-active-projects
    opencortex::context-get-recent-completed-tasks opencortex::context-list-all-skills
    opencortex::context-get-system-logs opencortex::context-assemble-global-awareness
    opencortex::org-object-id opencortex::org-object-type opencortex::org-object-attributes
    opencortex::org-object-content opencortex::org-object-parent-id
    opencortex::org-object-children opencortex::org-object-version
    opencortex::org-object-last-sync opencortex::org-object-hash
    opencortex::org-object-vector
    ;; Essential macros and special operators
    declare ignore quote function lambda defun defvar defparameter defmacro
    ;; Safe I/O
    with-open-file write-string read-line
    ;; Package introspection
    find-package make-package in-package do-external-symbols find-symbol
    ;; Safe system interaction
    uiop:run-program uiop:getenv uiop:merge-pathnames* uiop:file-exists-p
    uiop:directory-exists-p uiop:read-file-string uiop:split-string
    ;; Time
    get-universal-time get-internal-real-time sleep
    ;; Equality
    equalp = equal eq eql))
  "Static whitelist of symbols permitted in the Lisp Validator sandbox."

(defvar *lisp-validator-registry* nil
  "List of dynamically registered safe symbols.")

(defun lisp-validator-register (symbols)
  "Adds symbols to the global validator registry."
  (setf *lisp-validator-registry*
        (append *lisp-validator-registry*
                (if (listp symbols) symbols (list symbols))))
  (harness-log "LISP VALIDATOR: Registered ~a new safe symbols."
               (length (if (listp symbols) symbols (list symbols)))))

(defun lisp-validator-is-safe (symbol)
  "Checks if a symbol is in the static whitelist or the dynamic registry."
  (or (member symbol *lisp-validator-whitelist* :test #'string-equal)
      (member symbol *lisp-validator-registry* :test #'string-equal)))

(defun lisp-validator-ast-walk (form)
  "Recursively walks the Lisp AST. Returns T if safe, NIL if unsafe."
  (cond
    ;; Self-evaluating objects are safe.
    ((or (stringp form) (numberp form) (keywordp form) (characterp form)) t)
    ;; Symbols used as variables (in non-function position)
    ((symbolp form) (lisp-validator-is-safe form))
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

(defun lisp-validator-check-semantic (code-string)
  "Checks if all symbols in CODE-STRING are whitelisted.
Returns (VALUES t nil) if clean, or (VALUES nil reason-string nil nil)."
  (handler-case
      (let ((*read-eval* nil))
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof)
                until (eq form :eof)
                do (unless (lisp-validator-ast-walk form)
                     (return-from lisp-validator-check-semantic
                       (values nil "Code contains non-whitelisted symbols." nil nil)))))
        (values t nil nil nil))
    (error (c)
      (values nil (format nil "Semantic check failed: ~a" c) nil nil))))

(defun lisp-validator-validate (code-string &key strict)
  "Validates Lisp code through structural, syntactic, and optional semantic checks.
Returns a plist:
  (:status :success :checks (:structural t :syntactic t :semantic t))
or
  (:status :error :failed <check-key> :reason <string> :line <n> :col <n>)

When STRICT is non-nil, the semantic whitelist check is enforced.
When STRICT is nil, semantic check is skipped for general validation."
  (let ((structural-ok nil) (syntactic-ok nil) (semantic-ok nil)
        (reason nil) (line nil) (col nil))
    ;; Phase 1: Structural
    (multiple-value-setq (structural-ok reason line col)
      (lisp-validator-check-structural code-string))
    (unless structural-ok
      (return-from lisp-validator-validate
        (list :status :error :failed :structural :reason reason :line line :col col)))
    ;; Phase 2: Syntactic
    (multiple-value-setq (syntactic-ok reason line col)
      (lisp-validator-check-syntactic code-string))
    (unless syntactic-ok
      (return-from lisp-validator-validate
        (list :status :error :failed :syntactic :reason reason :line line :col col)))
    ;; Phase 3: Semantic (only when strict)
    (when strict
      (multiple-value-setq (semantic-ok reason line col)
        (lisp-validator-check-semantic code-string))
      (unless semantic-ok
        (return-from lisp-validator-validate
          (list :status :error :failed :semantic :reason reason :line line :col col))))
    ;; All clear
    (list :status :success
          :checks (list :structural t :syntactic t :semantic (or (not strict) semantic-ok)))))

(def-cognitive-tool :validate-lisp
  "Deterministically validates Lisp code for structural, syntactic, and semantic correctness.
Use this BEFORE declaring any Lisp code edit complete."
  ((:code :type :string :description "The Lisp code string to validate.")
   (:strict :type :boolean :description "If non-nil, enforces the semantic whitelist."))
  :body (lambda (args)
          (let ((code (getf args :code))
                (strict (getf args :strict)))
            (if (and code (stringp code))
                (lisp-validator-validate code :strict strict)
                (list :status :error :reason "Missing :code argument.")))))

(defskill :skill-lisp-validator
  :priority 900
  :trigger (lambda (ctx)
             ;; Trigger on any eval or shell action, or when validation is explicitly requested
             (let ((candidate (getf ctx :approved-action)))
               (when candidate
                 (let ((payload (getf candidate :payload)))
                   (member (getf payload :action) '(:eval :shell))))))
  :probabilistic nil
  :deterministic (lambda (action context)
                   (declare (ignore context))
                   (let ((payload (getf action :payload)))
                     (if (eq (getf payload :action) :eval)
                         (let* ((code (getf payload :code))
                                (result (lisp-validator-validate code :strict t)))
                           (if (eq (getf result :status) :error)
                               (progn
                                 (harness-log "LISP VALIDATOR: Blocked unsafe :eval action. ~a"
                                              (getf result :reason))
                                 (list :type :LOG
                                       :payload (list :level :error
                                                      :text (format nil "LISP VALIDATOR: Blocked unsafe eval. ~a"
                                                                    (getf result :reason)))))
                               action))
                         action))))
