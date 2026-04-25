(in-package :opencortex)

(defun verify-git-clean-p (&optional (dir *project-root*))
  "Returns T if the git repository at DIR has no uncommitted changes."
  (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                  :output :string
                                  :ignore-error-status t)))
    (string= "" (string-trim '(#\Space #\Newline #\Tab) status))))

(defskill :skill-engineering-standards
  :priority 1000
  :trigger (lambda (ctx) t)
  :probabilistic nil
  :deterministic (lambda (action context)
                    (declare (ignore action))
                    (let ((dirty (verify-git-clean-p)))
                      (unless dirty
                        (harness-log "ENGINEERING STANDARDS: Warning - Working tree is dirty. Commit before modifying files.")))
                    nil))
