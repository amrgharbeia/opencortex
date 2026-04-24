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
          (let ((code (getf args :code))
                (balanced (self-edit-balance-parens code)))
            (handler-case
                (progn
                  (read-from-string balanced)
                  (list :status :success :repaired balanced))
              (error (c)
                (list :status :error :message (format nil "Could not repair: ~a" c)))))))
