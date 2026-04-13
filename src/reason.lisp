(in-package :org-agent)

;; --- 1. Probabilistic Mechanisms ---

(defvar *probabilistic-backends* (make-hash-table :test 'equal))
(defvar *provider-cascade* nil)
(defvar *model-selector-fn* nil)
(defvar *consensus-enabled-p* nil)

(defun register-probabilistic-backend (name fn)
  (setf (gethash name *probabilistic-backends*) fn))

(defun probabilistic-call (prompt &key (system-prompt "You are the Probabilistic engine.") (cascade nil) (context nil))
  "Dispatches a neural request through the provider cascade."
  (let ((backends (or cascade *provider-cascade*)))
    (or (dolist (backend backends)
          (let ((backend-fn (gethash backend *probabilistic-backends*)))
            (when backend-fn
              (harness-log "PROBABILISTIC: Attempting backend ~a..." backend)
              (let* ((model (when *model-selector-fn* (funcall *model-selector-fn* backend context)))
                     (result (if model 
                                 (funcall backend-fn prompt system-prompt :model model)
                                 (funcall backend-fn prompt system-prompt))))
                (unless (or (null result) (search ":LOG" result))
                  (return result))))))
        "(:type :LOG :payload (:text \"Neural Cascade Failure\"))")))

(defun think (context)
  "Generates a Lisp action proposal based on current context."
  (let ((active-skill (find-triggered-skill context))
        (tool-belt (generate-tool-belt-prompt))
        (global-context (context-assemble-global-awareness)))
    (if active-skill
        (let* ((prompt-generator (skill-probabilistic-prompt active-skill))
               (raw-prompt (when prompt-generator (funcall prompt-generator context)))
               (system-prompt (concatenate 'string "IDENTITY: Actuator for org-agent. MANDATE: ONE Lisp plist. " global-context " " tool-belt)))
          (if (and raw-prompt (> (length raw-prompt) 1))
              (let* ((thought (probabilistic-call raw-prompt :system-prompt system-prompt :context context))
                     (cleaned (string-trim '(#\Space #\Newline #\Tab) thought)))
                (handler-case (read-from-string cleaned)
                  (error (c) (list :type :EVENT :payload (list :sensor :syntax-error :code cleaned :error (format nil "~a" c))))))
              '(:type :LOG :payload (:text "Skill triggered (Deterministic only)"))))
        nil)))

;; --- 2. Deterministic Mechanisms ---

(defun deterministic-verify (proposed-action context)
  "Iterates through all skill deterministic-gates sorted by priority."
  (let ((current-action proposed-action)
        (skills nil))
    (maphash (lambda (name skill) (declare (ignore name)) (when (skill-deterministic-fn skill) (push skill skills))) *skills-registry*)
    (setf skills (sort skills #'> :key #'skill-priority))
    (dolist (skill skills)
      (let ((gate (skill-deterministic-fn skill)))
        (setf current-action (funcall gate current-action context))
        (when (and (listp current-action) (member (getf current-action :type) '(:LOG :EVENT)))
          (harness-log "DETERMINISTIC: Intercepted by skill '~a'" (skill-name skill))
          (return-from deterministic-verify current-action))))
    current-action))

;; --- 3. The Unified Entrypoint ---

(defun reason-gate (signal)
  "Unified Stage: Combines Probabilistic proposals and Deterministic verification."
  (unless (eq (getf signal :type) :EVENT) (return-from reason-gate signal))
  (let ((candidate (think signal)))
    (if candidate
        (setf (getf signal :approved-action) (deterministic-verify candidate signal))
        (setf (getf signal :approved-action) nil))
    (setf (getf signal :status) :reasoned)
    signal))
