(in-package :org-agent)

(defun task-integrity-check (action)
  "Enforces semantic GTD integrity rules on proposed actions."
  (let* ((payload (getf action :payload))
         (act (or (getf payload :action) (getf action :action)))
         (id (or (getf payload :id) (getf action :id)))
         (new-attrs (or (getf payload :attributes) (getf action :attributes))))
    (when (and (eq act :update-node) (equal (getf new-attrs :TODO) "DONE"))
      (let ((children (list-objects-with-attribute :PARENT id)))
        (when (some (lambda (child) (let ((todo (getf (org-object-attributes child) :TODO)))
                                      (and todo (not (equal todo "DONE")))))
                    children)
          (return-from task-integrity-check "Blocked by Task Integrity: Active children exist."))))
    nil))

(defun decide (proposed-action context)
  "The System 2 Safety Gate: validates or rejects proposed neural actions."
  ;; 1. Task Integrity Check (GTD Semantics)
  (let ((integrity-error (task-integrity-check proposed-action)))
    (when integrity-error
      (kernel-log "SYSTEM 2 [INTEGRITY]: ~a~%" integrity-error)
      (return-from decide (list :type :LOG :payload (list :text integrity-error)))))

  ;; 2. Skill-specific and Safety Checks
  (let ((active-skill (find-triggered-skill context)))
    (if (and proposed-action (listp proposed-action) active-skill)
        (let* ((symbolic-gate (skill-symbolic-fn active-skill))
               (payload (getf proposed-action :payload))
               (action (or (getf payload :action) (getf proposed-action :action)))
               (code (or (getf payload :code) (getf proposed-action :code))))
          ;; Global safety harness for EVAL
          (when (and (member (getf proposed-action :type) '(:request :REQUEST))
                     (member action '(:eval :EVAL)))
            (let ((harness-pkg (find-package :org-agent.skills.org-skill-safety-harness)))
              (when (and code harness-pkg)
                (unless (ignore-errors (uiop:symbol-call :org-agent.skills.org-skill-safety-harness :safety-harness-validate code))
                  (kernel-log "SYSTEM 2 [GLOBAL]: Security violation blocked.~%")
                  (return-from decide '(:type :LOG :payload (:text "Blocked by Global Safety Harness")))))))
          ;; Skill-specific verification
          (if symbolic-gate
              (let ((decision (funcall symbolic-gate proposed-action context)))
                (if decision 
                    (progn (kernel-log "SYSTEM 2: Verified by skill '~a'.~%" (skill-name active-skill)) decision)
                    (progn (kernel-log "SYSTEM 2: REJECTED by skill '~a'.~%" (skill-name active-skill))
                           '(:type :LOG :payload (:text "Action rejected by skill heuristics")))))
              (progn (kernel-log "SYSTEM 2: Verified (Implicitly safe for skill '~a').~%" (skill-name active-skill)) proposed-action)))
        proposed-action)))

(defun list-objects-with-attribute (attr-key attr-val)
  "Filters the Object Store for nodes having a specific attribute value."
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (equal (getf (org-object-attributes obj) attr-key) attr-val) (push obj results))) *object-store*)
    results))
