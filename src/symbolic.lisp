(in-package :org-agent)

(defun decide (proposed-action context)
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
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (equal (getf (org-object-attributes obj) attr-key) attr-val) (push obj results))) *object-store*)
    results))
