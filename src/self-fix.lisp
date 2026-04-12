(in-package :org-agent)

(defun self-fix-apply (action context)
  "Applies a surgical code fix and reloads the modified skill."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (target-file (getf payload :file))
         (old-code (getf payload :old))
         (new-code (getf payload :new))
         (is-skill (and (stringp (namestring target-file))
                        (search "skills/" (namestring target-file)))))
    
    (org-agent:snapshot-object-store)
    (org-agent:kernel-log "SELF-FIX - Attempting surgical fix on ~a..." target-file)
    
    (handler-case
        (if (uiop:file-exists-p target-file)
            (let ((content (uiop:read-file-string target-file)))
              (if (search old-code content)
                  (let ((new-content (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars old-code) content new-code)))
                    (with-open-file (out target-file :direction :output :if-exists :supersede)
                      (write-string new-content out))
                    
                    (if is-skill
                        (progn
                          (org-agent:kernel-log "SELF-FIX - Reloading modified skill ~a..." target-file)
                          (if (org-agent:load-skill-from-org target-file)
                              (progn
                                (org-agent:kernel-log "SELF-FIX SUCCESS - Applied and reloaded.")
                                t)
                              (progn
                                (org-agent:kernel-log "SELF-FIX FAILURE - Skill reload failed. Rolling back.")
                                (with-open-file (out target-file :direction :output :if-exists :supersede)
                                  (write-string content out))
                                (org-agent:rollback-object-store 0)
                                nil)))
                        (progn
                          (org-agent:kernel-log "SELF-FIX SUCCESS - Applied fix to file.")
                          t)))
                  (progn (org-agent:kernel-log "SELF-FIX FAILURE - Pattern not found.") nil)))
            (progn (org-agent:kernel-log "SELF-FIX FAILURE - File not found.") nil))
      (error (c)
        (org-agent:kernel-log "SELF-FIX CRASH - ~a. Rolling back." c)
        (org-agent:rollback-object-store 0)
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
