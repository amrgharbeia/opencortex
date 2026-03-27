(in-package :org-agent)

;;; ============================================================================
;;; System 2: The Symbolic Gatekeeper
;;; ============================================================================
;;; This module implements the 'Executive Function' of the kernel. 
;;; System 2 is responsible for 'Deterministic Reasoning'—applying strict rules,
;;; safety constraints, and logical checks to verify neural proposals. 
;;; It is slow but reliable, and it has the absolute power to overrule System 1.

(defun decide (proposed-action context)
  "The System 2 Deciding Stage.
   
   It subjects the proposal from System 1 to a battery of symbolic tests.
   1. It applies Global Safety Heuristics (e.g., preventing shell execution).
   2. It delegates domain-specific validation to the active skill's verify-fn.
   
   Returns an approved action intent, or a safe fallback (like a log message)."
  (let ((active-skill (find-triggered-skill context)))
    (if active-skill
        (let ((symbolic-gate (skill-symbolic-fn active-skill)))
          
          ;; --- GLOBAL SAFETY HEURISTIC #1: Block Shell Execution ---
          ;; We never allow the LLM to execute raw shell commands via Emacs eval.
          (when (and proposed-action (listp proposed-action)
                     (eq (getf proposed-action :type) :REQUEST)
                     (eq (getf (getf proposed-action :payload) :action) :eval))
            (let ((code (getf (getf proposed-action :payload) :code)))
              (when (and code (search "shell-command" code))
                (kernel-log "SYSTEM 2 [GLOBAL]: Security violation blocked (shell-command attempt).~%")
                (return-from decide '(:type :LOG :payload (:text "Blocked by Global Safety Heuristic"))))))

          ;; --- SKILL-SPECIFIC VALIDATION ---
          ;; If the skill provides a specific System 2 verification function, run it.
          (if symbolic-gate
              (let ((decision (funcall symbolic-gate proposed-action context)))
                (if decision
                    (progn
                      (kernel-log "SYSTEM 2: Verified by skill '~a'. Proceeding to Act.~%" (skill-name active-skill))
                      decision)
                    (progn
                      ;; If the skill's logic returns NIL, the proposal is rejected.
                      (kernel-log "SYSTEM 2: REJECTED by skill '~a'. Logic violation detected.~%" (skill-name active-skill))
                      '(:type :LOG :payload (:text "Action rejected by System 2 skill heuristics")))))
              
              ;; If the skill has no specific symbolic logic, we allow the proposal to pass.
              (progn
                (kernel-log "SYSTEM 2: Verified (Implicitly safe for skill '~a').~%" (skill-name active-skill))
                proposed-action)))
        
        ;; If no skill is active, we return NIL (nothing to decide).
        nil)))

(defun list-objects-with-attribute (attr-key attr-val)
  "Helper: Returns objects from the symbolic store where ATTR-KEY matches ATTR-VAL.
   Used by skills to perform relational checks (e.g., searching for active TODOs)."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (when (equal (getf (org-object-attributes obj) attr-key) attr-val)
                 (push obj results)))
             *object-store*)
    results))

