(in-package :opencortex)

(defun self-edit-count-char (char string)
  "Counts occurrences of CHAR in STRING."
  (loop for c across string count (char= c char)))

(defun self-edit-balance-parens (code)
  "Balances parentheses in CODE."
  (let ((opens (self-edit-count-char #\( code))
        (closes (self-edit-count-char #\) code)))
    (cond
      ((= opens closes) code)
      ((> opens closes)
       (concatenate 'string code (make-string (- opens closes) :initial-element #\))))
      ((> closes opens)
       (concatenate 'string (make-string (- closes opens) :initial-element #\() code)))))

(defun copy-hash-table (table)
  "Returns a shallow copy of a hash table."
  (let ((new-table (make-hash-table :test (hash-table-test table)
                                    :size (hash-table-count table))))
    (maphash (lambda (k v) (setf (gethash k new-table) v)) table)
    new-table))

(defun self-edit-parse-location (context)
  "Extracts file and line from error context payload."
  (let* ((payload (getf context :payload))
         (message (getf payload :message ""))
         (file (or (getf payload :file)
                   (when (search "file" message)
                     (car (cl-ppcre:all-matches-as-strings "[a-zA-Z0-9_/-]+\\.lisp" message)))))
         (line (or (getf payload :line)
                   (let ((match (cl-ppcre:scan-to-strings "line.?(\\d+)" message)))
                     (when match (parse-integer (aref match 0)))))))
    (list :file file :line line)))

(defun self-edit-apply (target-file old-code new-code)
  "Applies surgical edit to TARGET-FILE: replace OLD-CODE with NEW-CODE.
Returns list with :status and :message keys."
  (unless (uiop:file-exists-p target-file)
    (return-from self-edit-apply 
      (list :status :error :message (format nil "File not found: ~a" target-file))))
  
  (snapshot-memory)
  (harness-log "SELF-EDIT: Attempting surgical fix on ~a..." target-file)
  
  (let ((original-content (uiop:read-file-string target-file)))
    (handler-case
        (if (search old-code original-content)
            (let ((new-content (cl-ppcre:regex-replace-all 
                                (cl-ppcre:quote-meta-chars old-code) 
                                original-content 
                                new-code)))
              (with-open-file (out target-file :direction :output :if-exists :supersede)
                (write-string new-content out))
              (harness-log "SELF-EDIT: Edit applied successfully.")
              (list :status :success :message "Edit applied."))
            (progn
              (harness-log "SELF-EDIT: Pattern not found in file.")
              (list :status :error :message "Pattern not found in file.")))
      (error (c)
        (harness-log "SELF-EDIT: Edit failed: ~a" c)
        (rollback-memory 0)
        (list :status :error :message (format nil "Edit failed: ~a" c))))))

(def-cognitive-tool :self-edit
  "Applies a surgical code modification to a file with automatic rollback on failure."
  ((:file :type :string :description "Path to the target file")
   (:old :type :string :description "The code block to find")
   (:new :type :string :description "The code block to replace with"))
  :body (lambda (args)
          (let* ((file (getf args :file))
                 (old (getf args :old))
                 (new (getf args :new)))
            (self-edit-apply file old new))))

(defskill :skill-self-edit
  :priority 95
  :trigger (lambda (ctx)
             (let ((sensor (getf (getf ctx :payload) :sensor)))
               (member sensor '(:syntax-error :repair-request :self-edit))))
  :probabilistic (lambda (ctx)
                   (let ((sensor (getf (getf ctx :payload) :sensor)))
                     (cond
                       ((eq sensor :syntax-error)
                        "You are the Self-Edit Agent. A syntax error occurred. 
Provide a fixed version of the code as a lisp form.")
                       ((eq sensor :repair-request)
                        "You are the Self-Edit Agent. Apply the surgical fix to the file.")
                       (t nil))))
  :deterministic (lambda (action ctx)
                   (let* ((payload (getf ctx :payload))
                          (sensor (getf payload :sensor)))
                     (cond
                       ((eq sensor :syntax-error)
                        (let ((code (getf payload :code)))
                          (harness-log "SELF-EDIT: Fast paren balancing...")
                          (let ((balanced (self-edit-balance-parens code)))
                            (handler-case
                                (progn
                                  (read-from-string balanced)
                                  (harness-log "SELF-EDIT: Fast fix SUCCESS.")
                                  (list :status :success :repaired balanced))
                              (error ()
                                (harness-log "SELF-EDIT: Fast fix failed, need neural repair.")
                                (list :status :error :reason "needs-llm"))))))
                       ((eq sensor :repair-request)
                        (let ((file (getf payload :file))
                              (old (getf payload :old))
                              (new (getf payload :new)))
                          (self-edit-apply file old new)))
                       (t nil)))))

(def-cognitive-tool :balance-parens
  "Balances parentheses in a code string."
  ((:code :type :string :description "The code to balance"))
  :body (lambda (args)
          (let* ((code (getf args :code))
                 (balanced (self-edit-balance-parens code)))
            (handler-case
                (progn
                  (read-from-string balanced)
                  (list :status :success :repaired balanced))
              (error (c)
                (list :status :error :message (format nil "Could not repair: ~a" c)))))))

(defvar *self-edit-skills-backup* nil
  "Backup of skill registry before hot-reload.")

(defun self-edit-hot-reload-skill (skill-name gen-path)
  "Reloads a skill from its compiled .lisp source.

   Steps:
   1. Backup current *skills-registry*
   2. Compile the new skill file
   3. Merge new skill into registry
   4. Verify the skill loads without error
   5. If error, rollback to backup

   Returns (values :success t) or (values :error message)."
  (unless *skills-registry*
    (return-from self-edit-hot-reload-skill
      (values :error "Skills engine not initialized")))
  (unless (uiop:file-exists-p gen-path)
    (return-from self-edit-hot-reload-skill
      (values :error (format nil "Skill file not found: ~a" gen-path))))

  ;; Step 1: Backup registry
  (setf *self-edit-skills-backup* (copy-hash-table *skills-registry*))

  (handler-case
      (progn
        ;; Step 2: Compile new skill
        (let ((compiled (compile-file gen-path)))
          (unless compiled
            (error "Compilation returned nil")))
        ;; Step 3: Load the compiled skill
        (load gen-path)
        ;; Step 4: Verify skill is in registry
        (let ((skill (gethash (string skill-name) *skills-registry*)))
          (if skill
              (progn
                (harness-log "SELF-EDIT: Hot-reloaded skill ~a from ~a"
                             skill-name gen-path)
                (values :success t))
              (error "Skill not registered after reload"))))
    (error (e)
      ;; Step 5: Rollback
      (when *self-edit-skills-backup*
        (clrhash *skills-registry*)
        (maphash (lambda (k v) (setf (gethash k *skills-registry*) v))
                 *self-edit-skills-backup*))
      (harness-log "SELF-EDIT: Hot-reload FAILED for ~a: ~a" skill-name e)
      (values :error (format nil "Hot-reload failed: ~a" e)))))

(def-cognitive-tool :reload-skill
  "Hot-reloads a skill from its compiled source file without restarting the system."
  ((:skill-name :type :string :description "Name of the skill to reload (e.g. :skill-engineering-standards)")
   (:gen-path :type :string :description "Absolute path to the compiled .lisp file"))
  :body (lambda (args)
          (let ((name (getf args :skill-name))
                (path (getf args :gen-path)))
            (multiple-value-bind (status message) (self-edit-hot-reload-skill name path)
              (list :status status :message message)))))
