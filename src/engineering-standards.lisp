(in-package :org-agent)

(defun verify-git-clean-p (dir)
  "Returns T if the git repository at DIR has no uncommitted changes."
  (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                  :output :string
                                  :ignore-error-status t)))
    (string= "" (string-trim '(#\Space #\Newline #\Tab) status))))

(defun engineering-standards-gate (action context)
  "Physically enforces the 'Commit Before Modify' rule."
  (let* ((payload (getf action :payload))
         (act (or (getf payload :action) (getf action :action)))
         (target-file (getf payload :file)))
    
    ;; If the action involves modifying files, check git status
    (when (member act '(:modify-file :write-file :replace :rename-file :delete-file))
      (let ((proj-root (asdf:system-source-directory :org-agent)))
        (unless (verify-git-clean-p proj-root)
          (harness-log "DETERMINISTIC [Standards]: BLOCKING ACTION. Working tree is dirty. Commit changes before modification.")
          (return-from engineering-standards-gate
            (list :type :LOG :payload (list :text "Engineering Standard Violation: Working tree dirty. You MUST commit before modifying files."))))))
    
    action))

(org-agent:defskill :skill-engineering-standards
  :priority 900 ; High priority, runs before most skills
  :trigger (lambda (ctx) t) ; Always active
  :probabilistic nil
  :deterministic #'engineering-standards-gate)
