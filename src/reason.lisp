(in-package :opencortex)

(defvar *probabilistic-backends* (make-hash-table :test 'equal))
(defvar *provider-cascade* nil)
(defvar *model-selector-fn* nil)
(defvar *consensus-enabled-p* nil)

(defun register-probabilistic-backend (name fn)
  "Registers a neural provider (e.g., :gemini, :anthropic) with its calling function."
  (setf (gethash name *probabilistic-backends*) fn))

(defun probabilistic-call (prompt &key (system-prompt "You are the Probabilistic engine.") (cascade nil) (context nil))
  "Dispatches a neural request through the provider cascade. Returns a Lisp plist or a failure log."
  (let ((backends (or cascade *provider-cascade*)))
    (or (dolist (backend backends)
          (let ((backend-fn (gethash backend *probabilistic-backends*)))
            (when backend-fn
              (harness-log "PROBABILISTIC: Attempting backend ~a..." backend)
              (let* ((model (when *model-selector-fn* (funcall *model-selector-fn* backend context)))
                     (result (if model 
                                 (funcall backend-fn prompt system-prompt :model model)
                                 (funcall backend-fn prompt system-prompt))))
                ;; If the result is valid, return it.
                ;; If it is an error plist from the gateway, continue the cascade but log it.
                (cond ((and (listp result) (eq (getf result :status) :success))
                       (return (getf result :content)))
                      ((stringp result) (return result))
                      (t (harness-log "PROBABILISTIC: Backend ~a failed: ~a" backend (getf result :message))))))))
        ;; Final fallback if all backends in the cascade fail.
        (list :type :LOG :payload (list :text "Neural Cascade Failure: All providers exhausted.")))))

(defun think (context)
  "Generates a Lisp action proposal based on current context."
  (let* ((active-skill (find-triggered-skill context))
         (tool-belt (generate-tool-belt-prompt))
         (global-context (context-assemble-global-awareness))
         (system-logs (context-get-system-logs))
         (assistant-name (or (uiop:getenv "MEMEX_ASSISTANT") "Agent")))
    (if active-skill
        (let* ((prompt-generator (skill-probabilistic-prompt active-skill))
               (raw-prompt (when prompt-generator (funcall prompt-generator context)))
               (system-prompt (format nil "IDENTITY: Actuator for ~a. MANDATE: ONE Lisp plist. ~a ~a RECENT_LOGS: ~a" 
                                      assistant-name global-context tool-belt system-logs)))
          (if (and raw-prompt (> (length raw-prompt) 1))
              (let* ((thought (probabilistic-call raw-prompt :system-prompt system-prompt :context context))
                     ;; Ensure we are working with a string for read-from-string
                     (cleaned (if (stringp thought) (string-trim '(#\Space #\Newline #\Tab) thought) thought)))
                (if (stringp cleaned)
                    (let ((*read-eval* nil))
                      (handler-case (read-from-string cleaned)
                        (error (c) (list :type :EVENT :payload (list :sensor :syntax-error :code cleaned :error (format nil "~a" c))))))
                    cleaned))
              (list :type :LOG :payload (list :text (format nil "Skill '~a' triggered (Deterministic only)" (skill-name active-skill))))))
        nil)))

(defun deterministic-verify (proposed-action context)
  "Iterates through all skill deterministic-gates sorted by priority."
  (let ((current-action proposed-action)
        (skills nil))
    ;; 1. Collect and sort active gates
    (maphash (lambda (name skill) (declare (ignore name)) (when (skill-deterministic-fn skill) (push skill skills))) *skills-registry*)
    (setf skills (sort skills #'> :key #'skill-priority))
    
    ;; 2. Execute gates sequentially if their trigger allows
    (dolist (skill skills)
      (let ((trigger (skill-trigger-fn skill))
            (gate (skill-deterministic-fn skill)))
        (when (or (null trigger) (ignore-errors (funcall trigger context)))
          (let ((next-action (funcall gate current-action context)))
            ;; Interception occurs if the gate returns a signal (LOG/EVENT) AND the original was a REQUEST.
            ;; If the original was already a LOG/EVENT, we only intercept if the gate returns a NEW signal object.
            (let ((original-type (getf current-action :type)))
              (when (and (listp next-action) 
                         (member (getf next-action :type) '(:LOG :EVENT :log :event))
                         (or (not (member original-type '(:LOG :EVENT :log :event)))
                             (not (eq next-action current-action))))
                (harness-log "DETERMINISTIC: Intercepted by skill '~a'" (skill-name skill))
                (return-from deterministic-verify next-action)))
            (setf current-action next-action)))))
    current-action))

(defun reason-gate (signal)
  "Unified Stage: Combines Probabilistic proposals and Deterministic verification."
  ;; Only process events that haven't been reasoned yet.
  (unless (eq (getf signal :type) :EVENT) (return-from reason-gate signal))
  
  (let ((candidate (think signal)))
    (if candidate
        (setf (getf signal :approved-action) (deterministic-verify candidate signal))
        (setf (getf signal :approved-action) nil))
    (setf (getf signal :status) :reasoned)
    signal))
