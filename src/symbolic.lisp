(in-package :org-agent)

(defun decide (proposed-action context)
  (let ((active-skill (find-triggered-skill context)))
    (if active-skill
        (let ((symbolic-gate (skill-symbolic-fn active-skill)))
          (when (and proposed-action (listp proposed-action) (eq (getf proposed-action :type) :REQUEST) (eq (getf (getf proposed-action :payload) :action) :eval))
            (let ((code (getf (getf proposed-action :payload) :code)) (harness-pkg (find-package :org-agent.skills.org-skill-safety-harness)))
              (when harness-pkg (unless (ignore-errors (uiop:symbol-call :org-agent.skills.org-skill-safety-harness :safety-harness-validate code))
                                  (kernel-log "SYSTEM 2 [GLOBAL]: Security violation blocked.~%")
                                  (return-from decide '(:type :LOG :payload (:text "Blocked by Global Safety Harness")))))))
          (if symbolic-gate
              (let ((decision (funcall symbolic-gate proposed-action context)))
                (if decision (progn (kernel-log "SYSTEM 2: Verified by skill '~a'.~%" (skill-name active-skill)) decision)
                    (progn (kernel-log "SYSTEM 2: REJECTED by skill '~a'.~%" (skill-name active-skill))
                           '(:type :LOG :payload (:text "Action rejected by skill heuristics")))))
              (progn (kernel-log "SYSTEM 2: Verified (Implicitly safe for skill '~a').~%" (skill-name active-skill)) proposed-action)))
        nil)))

(defun list-objects-with-attribute (attr-key attr-val)
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (equal (getf (org-object-attributes obj) attr-key) attr-val) (push obj results))) *object-store*)
    results))
