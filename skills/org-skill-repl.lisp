;;;; org-skill-repl.lisp - REPL Skill
;;;; Generated from org-skill-repl.org

(in-package :opencortex)

(defvar *repl-package* :opencortex
  "Default package for REPL evaluations.")

(defvar *repl-history* nil
  "History of evaluated forms for session continuity.")

(defvar *repl-variables* (make-hash-table :test #'eq)
  "Cache of bound variables for inspection.")

(defun repl-eval (code-string &key (package *repl-package*))
  "Evaluate Lisp code and return (values result output error).
   - result: the return value as string
   - output: captured stdout
   - error: error message or nil on success"
  (let ((out (make-string-output-stream))
        (err (make-string-output-stream))
        (pkg (or (find-package package) (find-package :opencortex))))
    (handler-case
        (let* ((*standard-output* out)
               (*error-output* err)
               (*package* pkg)
               (*read-eval* nil)
               (result nil))
          (with-input-from-string (s code-string)
            (loop for form = (read s nil :eof) until (eq form :eof)
                  do (setf result (eval form))))
          (push code-string *repl-history*)
          (values
           (format nil "~a" result)
           (get-output-stream-string out)
           nil))
      (error (c)
        (values
         nil
         (get-output-stream-string out)
         (format nil "~a" c))))))

(defun repl-inspect (symbol-name &key (package *repl-package*))
  "Inspect a variable's value and structure."
  (let* ((pkg (or (find-package package) (find-package :opencortex)))
         (sym (find-symbol (string-upcase symbol-name) pkg)))
    (cond
      ((null sym)
       (format nil "Symbol ~a not found in package ~a" symbol-name package))
      ((boundp sym)
       (let ((val (symbol-value sym)))
         (format nil "~a = ~a~%Type: ~a~%~%"
                 sym val (type-of val))))
      ((fboundp sym)
       (format nil "~a is a function~%Args: ~a~%"
               sym (documentation sym 'function)))
      (t
       (format nil "~a is unbound" symbol-name)))))

(defun repl-list-vars (&key (package *repl-package*))
  "List all bound variables in the package."
  (let* ((pkg (or (find-package package) (find-package :opencortex)))
         (vars nil))
    (do-symbols (sym pkg)
      (when (boundp sym)
        (push (format nil "~a" sym) vars)))
    (sort vars #'string<)))

(defun repl-load-file (filepath)
  "Load a Lisp file into the current image."
  (handler-case
      (progn
        (load filepath)
        (format nil "Loaded ~a" filepath))
    (error (c)
      (format nil "Error loading ~a: ~a" filepath c))))

(defun repl-set-package (package-name)
  "Set the default package for REPL evaluations."
  (let ((pkg (find-package (string-upcase package-name))))
    (if pkg
        (setf *repl-package* pkg)
        (format nil "Package ~a not found" package-name))))

(defun repl-help ()
  "Return available REPL commands."
  (format nil "~%
REPL Skill Commands:
-------------------
(repl-eval \"code\" :package :opencortex)
  - Evaluate Lisp code, returns (values result output error)

(repl-inspect \"symbol\" :package :opencortex)
  - Inspect a variable or function

(repl-list-vars :package :opencortex)
  - List all bound variables

(repl-load-file \"/path/to/file.lisp\")
  - Load a file into the image

(repl-set-package :package-name)
  - Switch default package

(repl-help)
  - Show this message
"))

(defskill :skill-repl
  :priority 200
  :trigger (lambda (ctx) (declare (ignore ctx)) nil)
  :deterministic (lambda (action ctx) (declare (ignore action ctx)) nil))