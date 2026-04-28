(in-package :opencortex)

(defvar *engineering-std-project-root* nil
  "Path to the project root for enforcement checks.")

(defstruct engineering-violation
  (phase nil)
  (rule nil)
  (message nil)
  (severity nil))

(defun check-structural-balance (file-path)
  "Tier 1 Chaos: Verifies that a Lisp file is syntactically balanced."
  (handler-case
      (with-open-file (s file-path)
        (loop for form = (read s nil :eof)
              until (eq form :eof))
        t)
    (error (c)
      (harness-log "CHAOS ERROR [Tier 1]: ~a in ~a" c file-path)
      nil)))

(defun verify-git-clean-p (&optional (dir *engineering-std-project-root*))
  "Returns T if the git repository at DIR has no uncommitted changes."
  (when dir
    (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                    :output :string
                                    :ignore-error-status t)))
      (string= "" (string-trim '(#\Space #\Newline #\Tab) status)))))

(defun engineering-std-init ()
  "Initialize the enforcement system."
  (let ((env-root (or (uiop:getenv "OC_DATA_DIR")
                       "/home/user/.local/share/opencortex")))
    (setf *engineering-std-project-root* (uiop:ensure-directory-pathname env-root))
    (harness-log "ENGINEERING STANDARDS: CDD Protocol Active.")))

(engineering-std-init)
