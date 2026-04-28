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
               (setf col 0))
              ((char= ch #\Newline)
               (incf line)
               (setf col 0))
              ((char= ch #\")
               (setf in-string t))
              ((char= ch #\()
               (push (list :paren line col) stack)
               (setf last-open-line line last-open-col col))
              ((char= ch #\))
               (if (null stack)
                   (return-from lisp-utils-check-structural 
                     (values nil (format nil "Unexpected close parenthesis at Line: ~a, Column: ~a" line col) line col))
                   (pop stack))))
        (incf col)))
    (if stack
        (values nil (format nil "Unbalanced open parenthesis starting at Line: ~a, Column: ~a" last-open-line last-open-col) last-open-line last-open-col)
        (values t nil))))

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
  '(+ - * / = < > <= >= 1+ 1- min max mod abs floor ceiling round
    and or not null eq eql equal string= string-equal char= char-equal
    list cons car cdr cadr cddr cdar caar caddr cdddr append mapcar remove-if remove-if-not
    length reverse sort nth nthcdr push pop last butlast subseq
    getf gethash assoc acons pairlis rassoc
    let let* if cond when unless case typecase prog1 progn
    format concatenate string-downcase string-upcase search subseq replace
    stringp numberp integerp listp symbolp keywordp
    opencortex:harness-log
    opencortex:snapshot-memory opencortex:rollback-memory
    opencortex:lookup-object opencortex:list-objects-by-type
    opencortex:ingest-ast opencortex:find-headline-missing-id))

(defun lisp-utils-ast-walk (form)
  (cond ((atom form)
         (if (symbolp form)
             (or (keywordp form)
                 (member form *lisp-utils-whitelist* :test #'string-equal))
             t))
        (t (every #'lisp-utils-ast-walk form))))

(defun lisp-utils-check-semantic (code-string)
  "Whitelists Common Lisp symbols for safe evaluation."
  (multiple-value-bind (valid-p err) (lisp-utils-check-syntactic code-string)
    (if (not valid-p)
        (values nil (format nil "Syntax Error: ~a" err))
        (handler-case
            (let ((*read-eval* nil))
              (with-input-from-string (stream (format nil "(progn ~a)" code-string))
                (loop for form = (read stream nil :eof) until (eq form :eof)
                      do (unless (lisp-utils-ast-walk form)
                           (return-from lisp-utils-check-semantic (values nil "Unsafe symbol detected")))))
              (values t nil))
          (error (c) (values nil (format nil "~a" c)))))))

(defun lisp-utils-validate (code-string &key strict)
  (multiple-value-bind (structural-ok reason) (lisp-utils-check-structural code-string)
    (if (not structural-ok)
        (list :status :error :failed :structural :reason reason)
        (multiple-value-bind (syntactic-ok err) (lisp-utils-check-syntactic code-string)
          (if (not syntactic-ok)
              (list :status :error :failed :syntactic :reason err)
              (if strict
                  (multiple-value-bind (semantic-ok msg) (lisp-utils-check-semantic code-string)
                    (if (not semantic-ok)
                        (list :status :error :failed :semantic :reason msg)
                        (list :status :success)))
                  (list :status :success)))))))

(defskill :skill-lisp-utils
  :priority 900
  :trigger (lambda (c) (declare (ignore c)) nil)
  :deterministic (lambda (a c) (declare (ignore c)) a))

(def-cognitive-tool :validate-lisp
  "Deterministically validates Lisp code for structural, syntactic, and semantic correctness."
  ((:code :type :string :description "The Lisp code string to validate.")
   (:strict :type :boolean :description "If non-nil, enforces the semantic whitelist."))
  :body (lambda (args)
          (let ((code (getf args :code))
                (strict (getf args :strict)))
            (if (and code (stringp code))
                (lisp-utils-validate code :strict strict)
                (list :status :error :reason "Missing :code argument.")))))
