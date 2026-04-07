(in-package :org-agent)

(defun get-env (var &optional default) (or (uiop:getenv var) default))

(defvar *auth-providers* (make-hash-table :test 'equal))
(defun register-auth-provider (name fn) (setf (gethash name *auth-providers*) fn))
(defun get-provider-auth (provider)
  "Retrieves authentication credentials for a provider.
   Supports direct plists, functions, or specific environment variable fallbacks."
  (let ((auth (gethash provider *auth-providers*)))
    (cond
      ((functionp auth) (funcall auth))
      ((listp auth) auth)
      (t 
       (let ((specific-key (case provider
                             (:gemini (uiop:getenv "GEMINI_API_KEY"))
                             (:openrouter (uiop:getenv "OPENROUTER_API_KEY"))
                             (:anthropic (uiop:getenv "ANTHROPIC_API_KEY"))
                             (:openai (uiop:getenv "OPENAI_API_KEY"))
                             (t nil))))
         (if (and specific-key (> (length specific-key) 0))
             (list :api-key specific-key)
             ;; Final fallback to the legacy generic key
             (let ((legacy (uiop:getenv "LLM_API_KEY")))
               (when (and legacy (> (length legacy) 0))
                 (list :api-key legacy)))))))))

(defvar *neuro-backends* (make-hash-table :test 'equal))
(defvar *provider-cascade* '(:openrouter :gemini))
(defun register-neuro-backend (name fn) (setf (gethash name *neuro-backends*) fn))

(defun ask-neuro (prompt &key (system-prompt "You are the System 1 engine of a Neurosymbolic Lisp Machine.") (cascade nil) (context nil))
  "Dispatches a neural request through the provider cascade.
   If CASCADE is a function, it is called with CONTEXT to determine backends."
  (let ((backends (cond
                    ((and cascade (listp cascade)) cascade)
                    ((functionp cascade) (funcall cascade context))
                    ((functionp *provider-cascade*) (funcall *provider-cascade* context))
                    (t *provider-cascade*))))
    (dolist (backend backends)
      (let ((backend-fn (gethash backend *neuro-backends*)))
        (when backend-fn
          (kernel-log "SYSTEM 1: Attempting backend ~a..." backend)
          (let* (;; Consult the Economist for the model ID if available
                 (model (ignore-errors 
                         (uiop:symbol-call :org-agent.skills.org-skill-economist :economist-get-model-for-provider backend)))
                 (result (if model 
                             (funcall backend-fn prompt system-prompt :model model)
                             (funcall backend-fn prompt system-prompt))))
            (if (and (stringp result) (search ":LOG" result) (or (search "Failure" result) (search "missing" result)))
                (kernel-log "SYSTEM 1: Backend ~a failed. Falling back..." backend)
                (return-from ask-neuro result))))))
    "(:type :LOG :payload (:text \"Neural Cascade Failure\"))"))

(defun execute-gemini-request (prompt system-prompt &key model)
  (let* ((auth (get-provider-auth :gemini)) (api-key (getf auth :api-key)) (bearer-token (getf auth :bearer-token))
         (endpoint-base (if model (format nil "https://generativelanguage.googleapis.com/v1/models/~a:generateContent" model)
                            "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent")))
    (unless (or api-key bearer-token) (return-from execute-gemini-request "(:type :LOG :payload (:text \"Authentication missing\"))"))
    (let* ((url (if api-key (format nil "~a?key=~a" endpoint-base api-key) endpoint-base))
           (headers `(("Content-Type" . "application/json") ,@(when bearer-token `(("Authorization" . ,(format nil "Bearer ~a" bearer-token))))))
           (body (cl-json:encode-json-to-string `((contents . ((parts . ((text . ,(format nil "~a~%~%Prompt: ~a" system-prompt prompt))))))))))
      (handler-case (let* ((response (dex:post url :headers headers :content body :connect-timeout 10 :read-timeout 30)) (json (cl-json:decode-json-from-string response)))
                      (cdr (assoc :text (cdr (assoc :parts (car (cdr (assoc :parts (car (cdr (assoc :candidates json)))))))))))
        (error (c) (format nil "(:type :LOG :payload (:text \"Neural Engine Failure: ~a\"))" c))))))

(defun execute-openrouter-request (prompt system-prompt &key model)
  (let ((api-key (uiop:getenv "OPENROUTER_API_KEY"))
        (endpoint "https://openrouter.ai/api/v1/chat/completions")
        (model-id (or model "google/gemini-2.0-flash-001")))
    (unless api-key (return-from execute-openrouter-request "(:type :LOG :payload (:text \"OpenRouter API Key missing\"))"))
    (let* ((headers `(("Content-Type" . "application/json")
                      ("Authorization" . ,(format nil "Bearer ~a" api-key))
                      ("HTTP-Referer" . "https://github.com/amr/org-agent")))
           (body (cl-ppcre:regex-replace-all "\\\\/" 
                                             (cl-json:encode-json-to-string
                                              `((model . ,model-id)
                                                (messages . (( (role . "system") (content . ,system-prompt) )
                                                             ( (role . "user") (content . ,prompt) )))))
                                             "/")))
      (kernel-log "OPENROUTER DEBUG - Body: ~a" body)
      (handler-case (let* ((response (dex:post endpoint :headers headers :content body :connect-timeout 10 :read-timeout 30)))
                      (kernel-log "OPENROUTER DEBUG - Raw Response: ~a" response)
                      (let ((json (cl-json:decode-json-from-string response)))
                        (cdr (assoc :content (cdr (assoc :message (car (cdr (assoc :choices json)))))))))
        (error (c) 
          (kernel-log "OPENROUTER ERROR: ~a" c)
          (format nil "(:type :LOG :payload (:text \"OpenRouter Failure: ~a\"))" c))))))

(defun openrouter-get-available-models ()
  "Fetches available models from OpenRouter."
  (let ((api-key (uiop:getenv "OPENROUTER_API_KEY")))
    (unless api-key (return-from openrouter-get-available-models nil))
    (let ((headers `(("Authorization" . ,(format nil "Bearer ~a" api-key)))))
      (handler-case
          (let* ((response (dex:get "https://openrouter.ai/api/v1/models" 
                                   :headers headers 
                                   :connect-timeout 60 
                                   :read-timeout 60))
                 (json (cl-json:decode-json-from-string response))
                 (data (cdr (assoc :data json)))
                 (results nil))
            (dolist (item data)
              (let ((id (cdr (assoc :id item)))
                    (context-len (cdr (assoc :context--length item))))
                (when id
                  (push (list :id id :context (format nil "~a" (or context-len "unknown"))) results))))
            (nreverse results))
        (error (c) 
          (kernel-log "Model Discovery Error: ~a" c)
          nil)))))

;; --- Sovereign Service Stubs ---
;; These are implemented in specialized skills but registered in the kernel namespace.

(defun economist-route-task (complexity)
  "Stub for Neuro-Economic routing. Overridden by skill-economist."
  (declare (ignore complexity))
  :gemini) ; Default fallback

(defun org-id-new ()
  "Stub for Sovereign ID generation. Overridden by skill-ast-normalization."
  (format nil "node-~a" (get-universal-time)))

(register-neuro-backend :gemini #'execute-gemini-request)
(register-neuro-backend :openrouter #'execute-openrouter-request)
(setf *provider-cascade* '(:openrouter :gemini))

(defun think (context)
  (let ((active-skill (find-triggered-skill context)))
    (if active-skill
        (progn
          (kernel-log "SYSTEM 1: Engaging skill '~a'~%" (skill-name active-skill))
          (let* ((prompt-generator (skill-neuro-prompt active-skill)) 
                 (prompt (when prompt-generator (funcall prompt-generator context))))
            (if prompt 
                (let* ((thought (ask-neuro prompt :context context))
                       ;; Improved cleaning: Extract content between ``` blocks if they exist
                       (cleaned-thought 
                        (let ((match (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" thought)))
                          (if match
                              (let ((regs (nth-value 1 (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" thought))))
                                (if (and regs (> (length regs) 0)) (elt regs 0) thought))
                              (string-trim '(#\Space #\Newline #\Tab) thought))))
                       (suggestion (ignore-errors (read-from-string cleaned-thought))))
                  (kernel-log "SYSTEM 1 Suggestion: ~a~%" cleaned-thought)
                  (cond
                    ((and suggestion (listp suggestion)) suggestion)
                    ;; SALVAGE: If LLM returned plain text or a non-list symbol
                    ((and (let ((p (getf context :payload))) (eq (getf p :sensor) :chat-message))
                          (> (length cleaned-thought) 0))
                     (kernel-log "SYSTEM 1: SALVAGING plain-text response.~%")
                     (let* ((no-prefix (cl-ppcre:regex-replace "(?i)^(okay,? |sure,? |i will |i've |i have |here is |got it\\.? |understood\\.? |done\\.? |yes,? )+" cleaned-thought "")))
                       `(:target :emacs :payload (:action :insert-at-end :buffer "*org-agent-chat*" :text ,no-prefix))))
                    (t 
                     (kernel-log "SYSTEM 1 ERROR: Could not parse response as Lisp plist.~%")
                     nil)))
                '(:type :LOG :payload (:text "Skill triggered (Deterministic only)")))))
        nil)))

(defun distill-prompt (full-prompt successful-output)
  (let ((system-instr "You are a Meta-Cognitive Prompt Architect. DISTILL into template."))
    (ask-neuro (format nil "PROMPT: ~a~%RESULT: ~a" full-prompt successful-output) :system-prompt system-instr)))

(defun distillation-loop ()
  "Autonomous distillation cycle (Skeletal)."
  (kernel-log "NEURO [Evolution] - Distillation cycle triggered."))
