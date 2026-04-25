(defvar *engineering-std-*project-root* nil
  "Path to the project root for enforcement checks.")

(defun engineering-std-set-project-root (path)
  (setf *engineering-std-*project-root* (uiop:ensure-directory-pathname path)))

(defstruct engineering-violation
  (phase nil)
  (rule nil)
  (message nil)
  (severity nil))

(defvar *enforcement-rules*
  '((:pre-task
     (:git-clean "Working tree must be clean before modifications")
     (:skill-queried "Skill catalog should be queried before analysis")
     (:tangle-synced "Tangled .lisp files must match Org source"))
    (:during-task
     (:org-only "Only .org files may be edited; .lisp is generated")
     (:one-per-block "One definition per src block")
     (:prose-required "Every block must have preceding prose"))
    (:post-task
     (:tests-pass "All tests must pass")
     (:no-artifacts "No orphaned .bak, .log, .tmp files"))))

(defun verify-git-clean-p (&optional (dir *engineering-std-*project-root*))
  "Returns T if the git repository at DIR has no uncommitted changes."
  (when dir
    (let ((status (uiop:run-program (list "git" "-C" (namestring dir) "status" "--porcelain")
                                    :output :string
                                    :ignore-error-status t)))
      (string= "" (string-trim '(#\Space #\Newline #\Tab) status)))))

(defun check-git-clean (&optional (dir *engineering-std-*project-root*))
  "Returns violation if git is dirty, nil if clean."
  (unless (verify-git-clean-p dir)
    (make-engineering-violation
     :phase :pre-task
     :rule :git-clean
     :message "ENGINEERING STANDARDS VIOLATION: Working tree is dirty. Commit changes before modifying files."
     :severity :blocker)))

(defvar *tangle-targets*
  '(("skills/org-skill-engineering-standards.org" . "library/gen/org-skill-engineering-standards.lisp")
    ("skills/org-skill-literate-programming.org" . "library/gen/org-skill-literate-programming.lisp")
    ("harness/memory.org" . "library/memory.lisp")
    ("harness/loop.org" . "library/loop.lisp")
    ("harness/perceive.org" . "library/perceive.lisp")
    ("harness/reason.org" . "library/reason.lisp")
    ("harness/act.org" . "library/act.lisp")
    ("harness/skills.org" . "library/skills.lisp")
    ("harness/communication.org" . "library/communication.lisp")))

(defun check-tangle-sync (&optional (root *engineering-std-*project-root*))
  "Returns violation if any tangled .lisp file is newer than its Org source.
  
This detects direct .lisp edits (which violate the LP workflow)."
  (when root
    (dolist (pair *tangle-targets*)
      (let* ((org-file (merge-pathnames (car pair) root))
             (lisp-file (merge-pathnames (cdr pair) root))
             (org-time (ignore-errors (file-write-date org-file)))
             (lisp-time (ignore-errors (file-write-date lisp-file))))
        (when (and org-time lisp-time (> lisp-time org-time))
          (return-from check-tangle-sync
            (make-engineering-violation
             :phase :pre-task
             :rule :tangle-synced
             :message (format nil "ENGINEERING STANDARDS VIOLATION: ~a is newer than ~a. Edit Org source, not .lisp directly."
                                    (file-namestring lisp-file) (file-namestring org-file))
             :severity :blocker))))))
  nil)

(defun engineering-standards-gate (action context)
  "The deterministic HARD BLOCK gate for Engineering Standards.

  BLOCKING checks (return :LOG on violation):
  - Git tree must be clean before file modifications

  WARNING checks (log only):
  - Skill catalog should be queried first

  Returns modified action, or :LOG/:EVENT on violation."
  (let* ((payload (getf action :payload))
         (tool (getf payload :tool))
         (file (getf payload :file))
         (code (getf payload :code))
         (modifies-files-p (or file code tool)))

    ;; BLOCKING: Git clean required for file modifications
    (when modifies-files-p
      (let ((git-check (check-git-clean *engineering-std-*project-root*)))
        (when git-check
          (harness-log "~a" (engineering-violation-message git-check))
          (return-from engineering-standards-gate
            (list :type :log
                  :payload (list :text (engineering-violation-message git-check))))))

    ;; BLOCKING: Tangle sync check - .lisp must not be newer than .org
    (let ((tangle-check (check-tangle-sync *engineering-std-*project-root*)))
      (when tangle-check
        (harness-log "~a" (engineering-violation-message tangle-check))
        (return-from engineering-standards-gate
          (list :type :log
                :payload (list :text (engineering-violation-message tangle-check))))))))

    action)

(defskill :skill-engineering-standards
  :priority 1000
  :trigger (lambda (ctx)
             (declare (ignore ctx))
             t)
  :probabilistic nil
  :deterministic #'engineering-standards-gate)

(defvar *engineering-std-initialized* nil)

(defun engineering-std-init ()
  "Initialize the enforcement system with project root."
  (unless *engineering-std-initialized*
    (let ((env-root (or (uiop:getenv "OPENCORTEX_ROOT")
                       (uiop:getenv "MEMEX_DIR")
                       "/home/user/memex/projects/opencortex")))
      (engineering-std-set-project-root env-root)
      (setf *engineering-std-initialized* t)
      (harness-log "ENGINEERING STANDARDS: Initialized with root ~a" *engineering-std-*project-root*))))

;; Auto-initialize on load
(engineering-std-init)
