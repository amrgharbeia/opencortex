(in-package :org-agent)

;;; ============================================================================
;;; System 1: The Neural Engine
;;; ============================================================================
;;; This module manages the connection to the LLM (Large Language Model).
;;; System 1 is responsible for 'Associative Thinking'—pattern matching over
;;; the user's notes and proposing intuitive actions. It is fast but unreliable,
;;; and its output must ALWAYS be verified by System 2.

;; Initialize environment from .env file at project root
(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((env-file (merge-pathnames ".env" (asdf:system-source-directory :org-agent))))
    (when (uiop:file-exists-p env-file)
      (cl-dotenv:load-env env-file))))

(defun get-env (var &optional default)
  "Helper: Fetches an environment variable with a fallback default."
  (or (uiop:getenv var) default))

;;; --- Pluggable Authentication Backends ---

(defvar *auth-providers* (make-hash-table :test 'equal)
  "Registry of authentication provider skills. Key is provider keyword (e.g., :gemini).")

(defun register-auth-provider (name fn)
  "Register a function that returns the required auth headers for a provider."
  (setf (gethash name *auth-providers*) fn))

(defun get-provider-auth (provider)
  "Queries the registered auth skill for the necessary headers."
  (let ((auth-fn (gethash provider *auth-providers*)))
    (if auth-fn
        (funcall auth-fn)
        nil)))

(defvar *neuro-backends* (make-hash-table :test 'equal)
  "Registry of neural provider backends.")

(defvar *provider-cascade* '(:gemini)
  "Ordered list of backends to try for each request.")

(defun register-neuro-backend (name fn)
  "Register a function to handle LLM requests for a specific backend."
  (setf (gethash name *neuro-backends*) fn))

(defun ask-neuro (prompt &key (system-prompt "You are the System 1 (Neural) engine of a Neurosymbolic Lisp Machine. Provide concise, high-fidelity suggestions in Lisp plist format.") (cascade nil))
  "Dispatches a prompt to the registered neural backends in order of preference."
  (let ((backends (or cascade *provider-cascade*)))
    (dolist (backend backends)
      (let ((backend-fn (gethash backend *neuro-backends*)))
        (when backend-fn
          (kernel-log "SYSTEM 1: Attempting backend ~a..." backend)
          (let ((result (funcall backend-fn prompt system-prompt)))
            ;; Check if the result indicates failure
            (if (and (stringp result) (search ":LOG" result) (search "Failure" result))
                (kernel-log "SYSTEM 1: Backend ~a failed. Falling back..." backend)
                (return-from ask-neuro result)))))))
    ;; If we fall through, the entire cascade failed
    "(:type :LOG :payload (:text \"Neural Cascade Failure - All providers exhausted.\"))")

(defun execute-gemini-request (prompt system-prompt)
  "The default System 1 backend (Gemini). Authentication is now pluggable."
  (let* ((auth (get-provider-auth :gemini))
         (api-key (getf auth :api-key))
         (bearer-token (getf auth :bearer-token))
         (endpoint (or (getf auth :endpoint) 
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")))
    
    (unless (or api-key bearer-token)
      (return-from execute-gemini-request "(:type :LOG :payload (:text \"Authentication missing for Gemini\"))"))
    
    (let* ((url (if api-key (format nil "~a?key=~a" endpoint api-key) endpoint))
           (headers `(("Content-Type" . "application/json")
                      ,@(when bearer-token `(("Authorization" . ,(format nil "Bearer ~a" bearer-token))))))
           (body (cl-json:encode-json-to-string
                  `((contents . ((parts . ((text . ,(format nil "~a~%~%Prompt: ~a" system-prompt prompt))))))))))
      (handler-case
          (let* ((response (dex:post url :headers headers :content body))
                 (json (cl-json:decode-json-from-string response)))
            (cdr (assoc :text (cdr (assoc :parts (car (cdr (assoc :parts (car (cdr (assoc :candidates json)))))))))))
        (error (c)
          (format nil "(:type :LOG :payload (:text \"Neural Engine Failure: ~a\"))" c))))))

;; Initialize the default backend
(register-neuro-backend :gemini #'execute-gemini-request)

(defun think (context)
  "The System 1 Thinking Stage. 
   
   It dispatches to the Skill Registry to find an active skill. If found, 
   it executes that skill's neuro-prompt generator and queries the LLM.
   
   Returns a proposed action plist (unverified)."
  (let ((active-skill (find-triggered-skill context)))
    (if active-skill
        (progn
          (kernel-log "SYSTEM 1: Engaging skill '~a'~%" (skill-name active-skill))
          (let* ((prompt-generator (skill-neuro-prompt active-skill))
                 ;; Execute the skill's Lisp code to build the LLM prompt.
                 (prompt (when prompt-generator (funcall prompt-generator context))))
            (if prompt
                (let* ((thought (ask-neuro prompt))
                       ;; Read the LLM string back into a native Lisp data structure.
                       (suggestion (ignore-errors (read-from-string thought))))
                  (kernel-log "SYSTEM 1 Suggestion: ~a~%" thought)
                  suggestion)
                ;; If the skill has no neuro-prompt, it's a 'Deterministic Skill' (Symbolic-only).
                '(:type :LOG :payload (:text "Skill triggered (Deterministic only)")))))
        ;; If no skills trigger, the agent remains silent.
        nil)))

;;; ============================================================================
;;; Prompt Distillation (Self-Evolution)
;;; ============================================================================

(defun distill-prompt (full-prompt successful-output)
  "Neural distillation: Summarizes a complex prompt and its success into a denser format.
   Used for 'Self-Evolving prompts' that reduce token usage over time."
  (let ((system-instr "You are a Meta-Cognitive Prompt Architect. Your task is to DISTILL the following prompt and its successful result into a SHORTER, HIGH-SIGNAL template that would yield the same result."))
    (ask-neuro (format nil "PROMPT: ~a~%RESULT: ~a~%~%Create a distilled version." full-prompt successful-output)
               :system-prompt system-instr)))

(defun distillation-loop ()
  "Periodically reviews internal logs and distills prompts for active skills.
   This is an autonomous self-improvement cycle."
  (let ((logs (context-get-system-logs 50)))
    (dolist (log logs)
      (when (search "Verified by skill" log)
        ;; Extract the skill name and attempt distillation
        (kernel-log "NEURO - Triggering prompt distillation cycle...")))))
