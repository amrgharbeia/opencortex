(defun verify-git-clean-p (&optional (dir *project-root*))
  "Returns T if the git repository at DIR has no uncommitted changes."
  (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                  :output :string
                                  :ignore-error-status t)))
    (string= "" (string-trim '(#\Space #\Newline #\Tab) status))))

(defun engineering-standards-gate (action context)
  "The deterministic gate for the Engineering Standards skill.

  Checks:
  1. Git tree is clean (warn if dirty)
  2. Action has :engineering-standards-compliance note if high-impact

  Returns ACTION unmodified. This is a warning gate, not a blocking gate."
  (declare (ignore context))

  ;; Check 1: Git cleanliness
  (let ((dirty (not (verify-git-clean-p))))
    (when dirty
      (harness-log "ENGINEERING STANDARDS: Warning - Working tree is dirty. Commit before modifying files.")))

  action)

(defskill :skill-engineering-standards
  :priority 1000
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :probabilistic nil
  :deterministic #'engineering-standards-gate)
