(in-package :opencortex)

(defun count-char (char string)
  "Counts occurrences of CHAR in STRING.
Returns an integer count."
  (let ((count 0))
    (loop for c across string
          when (char= c char)
            do (incf count))
    count))

(defun deterministic-repair (code)
  "Attempts instant fixes on broken Lisp code (e.g., balancing parens).
Returns the fixed code string."
  (let* ((open-parens (count-char #\( code))
         (close-parens (count-char #\) code))
         (diff (- open-parens close-parens)))
    (if (> diff 0)
        (concatenate 'string code (make-string diff :initial-element #\)))
        code)))

(defun neural-repair (code error-message)
  "Uses the Probabilistic Engine to deeply repair the syntax structure.
Returns the fixed code string."
  (let ((prompt (format nil "The following Lisp code failed to parse.
ERROR: ~a
CODE: ~a
MANDATE: Output EXACTLY ONE valid Common Lisp list. Do not explain. Do not use markdown blocks."
                        error-message code))
        (system-prompt "You are a Lisp Syntax Repair Actuator. Return only valid, balanced Lisp code."))
    (let ((repaired (ask-probabilistic prompt :system-prompt system-prompt)))
      (string-trim '(#\Space #\Newline #\Tab) repaired))))

(defun lisp-utils-check-structural (code-string)
  "Checks for balanced parens, brackets, and terminated strings.
Returns (VALUES t nil) if clean, or (VALUES nil reason-string line col)."
  (let ((stack nil)
        (in-string nil)
        (escaped nil)
        (line 1)
        (col 0)
        (last-open-line 1)
        (last-open-col 0))
    (dotimes (i (length code-string))
      (let ((ch (char code-string i)))
        (cond (escaped (setf escaped nil))
              ((char= ch #\\) (setf escaped t))
              (in-string
               (when (char= ch #\") (setf in-string nil)))
              ((char= ch #\;)
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
                      (return-from lisp-utils-check-structural
                        (values nil (format nil "Unexpected ')' at line ~a, col ~a" line col) line col)))
                     ((string= (caar stack) "[")
                      (return-from lisp-utils-check-structural
                        (values nil (format nil "Mismatched ']' expected at line ~a, col ~a" line col) line col)))
                     (t (pop stack))))
              ((char= ch #\])
               (cond ((null stack)
                      (return-from lisp-utils-check-structural
                        (values nil (format nil "Unexpected ']' at line ~a, col ~a" line col) line col)))
                     ((string= (caar stack) "(")
                      (return-from lisp-utils-check-structural
                        (values nil (format nil "Mismatched ')' expected at line ~a, col ~a" line col) line col)))
                     (t (pop stack))))
              ((char= ch #\Newline)
               (incf line) (setf col 0)))
        (unless (char= ch #\Newline) (incf col))))
    (if (null stack)
        (values t nil nil nil)
        (values nil (format nil "Unbalanced '~a' opened at line ~a, col ~a"
                            (caar stack) last-open-line last-open-col)
                last-open-line last-open-col))))

(defun lisp-utils-check-syntactic (code-string)
  "Checks if the code can be read by SBCL with *read-eval* nil.
Returns (VALUES t nil) if clean, or (VALUES nil error-message nil nil)."
  (handler-case
      (let ((*read-eval* nil))
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof) until (eq form :eof)))
        (values t nil nil nil))
    (error (c)
      (let ((msg (format nil "~a" c)))
        (values nil msg nil nil)))))

(defparameter *lisp-utils-whitelist*
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
    equalp = equal eq eql)
  "Static whitelist of symbols permitted in the Lisp Utils sandbox.")

(defun lisp-utils-ast-walk (form)
  "Recursively walks the Lisp AST. Returns T if safe, NIL if unsafe."
  (cond
    ((or (stringp form) (numberp form) (keywordp form) (characterp form)) t)
    ((symbolp form)
     (or (member form *lisp-utils-whitelist* :test #'string-equal)
         (member (format nil "~a" form) *lisp-utils-whitelist* :test #'string-equal)))
    ((listp form)
     (let ((head (car form)))
       (cond
         ((eq head 'quote) t)
         ((not (symbolp head)) nil)
         ((member head *lisp-utils-whitelist* :test #'string-equal)
          (every #'lisp-utils-ast-walk (cdr form)))
         (t
          (harness-log "LISP UTILS: Blocked call to non-whitelisted function ~a" head)
          nil))))
    (t nil)))

(defun lisp-utils-check-semantic (code-string)
  "Checks if all symbols in CODE-STRING are whitelisted.
Returns (VALUES t nil) if clean, or (VALUES nil reason-string nil nil)."
  (handler-case
      (let ((*read-eval* nil))
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof)
                until (eq form :eof)
                do (unless (lisp-utils-ast-walk form)
                     (return-from lisp-utils-check-semantic
                       (values nil "Code contains non-whitelisted symbols." nil nil)))))
        (values t nil nil nil))
    (error (c)
      (values nil (format nil "Semantic check failed: ~a" c) nil nil))))

(defun lisp-utils-validate (code-string &key strict)
  "Validates Lisp code through structural, syntactic, and optional semantic checks.
Returns a plist:
  (:status :success :checks (:structural t :syntactic t :semantic t))
or
  (:status :error :failed <check-key> :reason <string> :line <n> :col <n>)

When STRICT is non-nil, the semantic whitelist check is enforced."
  (let ((structural-ok nil) (syntactic-ok nil) (semantic-ok nil)
        (reason nil) (line nil) (col nil))
    ;; Phase 1: Structural
    (multiple-value-setq (structural-ok reason line col)
      (lisp-utils-check-structural code-string))
    (unless structural-ok
      (return-from lisp-utils-validate
        (list :status :error :failed :structural :reason reason :line line :col col)))
    ;; Phase 2: Syntactic
    (multiple-value-setq (syntactic-ok reason line col)
      (lisp-utils-check-syntactic code-string))
    (unless syntactic-ok
      (return-from lisp-utils-validate
        (list :status :error :failed :syntactic :reason reason :line line :col col)))
    ;; Phase 3: Semantic (only when strict)
    (when strict
      (multiple-value-setq (semantic-ok reason line col)
        (lisp-utils-check-semantic code-string))
      (unless semantic-ok
        (return-from lisp-utils-validate
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
                (lisp-utils-validate code :strict strict)
                (list :status :error :reason "Missing :code argument.")))))

(def-cognitive-tool :repair-lisp
  "Repairs broken Lisp code using deterministic first, then neural escalation."
  ((:code :type :string :description "The broken Lisp code string")
   (:error :type :string :description "The error message from parsing failure"))
  :body (lambda (args)
          (let ((code (getf args :code))
                (error-msg (getf args :error)))
            (if (and code error-msg)
                (let ((fast-fix (deterministic-repair code)))
                  (handler-case
                      (let ((repaired (read-from-string fast-fix)))
                        (format nil "~a" repaired))
                    (error ()
                      (let ((deep-fix (neural-repair code error-msg)))
                        (handler-case
                            (let ((repaired (read-from-string deep-fix)))
                              (format nil "~a" repaired))
                          (error ()
                            "REPAIR FAILED"))))))
                (list :status :error :reason "Missing :code or :error argument.")))))

(defskill :skill-lisp-repair
  :priority 90
  :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :syntax-error))
  :probabilistic nil
  :deterministic (lambda (action context)
                    (declare (ignore action))
                    (let* ((payload (getf context :payload))
                           (code (getf payload :code))
                           (error-msg (getf payload :error)))
                      (harness-log "LISP REPAIR: Reacting to syntax error...")
                      (let ((fast-fix (deterministic-repair code)))
                        (handler-case
                            (let ((repaired (read-from-string fast-fix)))
                              (harness-log "LISP REPAIR: Deterministic repair SUCCESS.")
                              repaired)
                          (error ()
                            (harness-log "LISP REPAIR: Deterministic failed. Escalating to neural...")
                            (let ((deep-fix (neural-repair code error-msg)))
                              (handler-case
                                  (let ((repaired (read-from-string deep-fix)))
                                    (harness-log "LISP REPAIR: Neural repair SUCCESS.")
                                    repaired)
                                (error ()
                                  (harness-log "LISP REPAIR: Neural repair failed.")
                                  (list :type :LOG :payload (list :text "Lisp Repair Failed.")))))))))))

(defskill :skill-lisp-validator
  :priority 900
  :trigger (lambda (ctx)
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
                                 (result (lisp-utils-validate code :strict t)))
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
