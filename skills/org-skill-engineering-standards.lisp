(in-package :opencortex)

(defun verify-git-clean-p (dir)
  "Checks if a directory has uncommitted changes."
  (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                 :output :string
                                 :ignore-error-status t)))
    (string= "" (string-trim '(#\Space #\Newline #\Tab) status))))

(defun engineering-standards-verify-lisp (code)
  "Enforces Lisp structural and semantic standards using utils-lisp."
  (let ((result (utils-lisp-validate code :strict t)))
    (if (eq (getf result :status) :success)
        t
        (error (getf result :reason)))))

(defun engineering-standards-format-lisp (code)
  "Ensures Lisp code adheres to formatting standards."
  (utils-lisp-format code))

(defskill :skill-engineering-standards
  :priority 100
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
