(in-package :opencortex)

(defun self-fix-apply (action context)
  "Applies a surgical code fix and reloads the modified skill."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (target-file (getf payload :file))
         (old-code (getf payload :old))
         (new-code (getf payload :new))
         (is-skill (and (stringp (namestring target-file))
                        (search "skills/" (namestring target-file)))))
    
    (opencortex:snapshot-memory)
    (opencortex:harness-log "SELF-FIX - Attempting surgical fix on ~a..." target-file)
    
    (handler-case
        (if (uiop:file-exists-p target-file)
            (let ((content (uiop:read-file-string target-file)))
              (if (search old-code content)
                  (let ((new-content (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars old-code) content new-code)))
                    (with-open-file (out target-file :direction :output :if-exists :supersede)
                      (write-string new-content out))
                    
                    (if is-skill
                        (progn
                          (opencortex:harness-log "SELF-FIX - Reloading modified skill ~a..." target-file)
                          (if (opencortex:load-skill-from-org target-file)
                              (progn
                                (opencortex:harness-log "SELF-FIX SUCCESS - Applied and reloaded.")
                                t)
                              (progn
                                (opencortex:harness-log "SELF-FIX FAILURE - Skill reload failed. Rolling back.")
                                (with-open-file (out target-file :direction :output :if-exists :supersede)
                                  (write-string content out))
                                (opencortex:rollback-memory 0)
                                nil)))
                        (progn
                          (opencortex:harness-log "SELF-FIX SUCCESS - Applied fix to file.")
                          t)))
                  (progn (opencortex:harness-log "SELF-FIX FAILURE - Pattern not found.") nil)))
            (progn (opencortex:harness-log "SELF-FIX FAILURE - File not found.") nil))
      (error (c)
        (opencortex:harness-log "SELF-FIX CRASH - ~a. Rolling back." c)
        (opencortex:rollback-memory 0)
        nil))))

(def-cognitive-tool :repair-file 
  "Applies a surgical code modification to a file and reloads the skill if applicable."
  ((:file :type :string :description "Path to the target file")
   (:old :type :string :description "The literal code block to find")
   (:new :type :string :description "The literal code block to replace it with"))
  :body (lambda (args)
          (if (self-fix-apply (list :payload args) nil)
              "REPAIR SUCCESSFUL."
              "REPAIR FAILED.")))

(defskill :skill-self-fix
  :priority 95
  :trigger (lambda (context) (eq (getf (getf context :payload) :sensor) :repair-request))
  :probabilistic (lambda (context)
           (format nil "You are the opencortex Repair Actuator. Synthesize a surgical fix for the reported failure.
Return a Lisp plist for :repair-file."))
  :deterministic (lambda (action context)
              (let ((payload (getf action :payload)))
                (self-fix-apply action context))))
