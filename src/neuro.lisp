(in-package :org-agent)

(defun get-env (var &optional default) (or (uiop:getenv var) default))

(defvar *auth-providers* (make-hash-table :test 'equal))
(defun register-auth-provider (name fn) (setf (gethash name *auth-providers*) fn))
(defun get-provider-auth (provider) (let ((auth-fn (gethash provider *auth-providers*))) (if auth-fn (funcall auth-fn) nil)))

(defvar *neuro-backends* (make-hash-table :test 'equal))
(defvar *provider-cascade* '(:gemini))
(defun register-neuro-backend (name fn) (setf (gethash name *neuro-backends*) fn))

(defun ask-neuro (prompt &key (system-prompt "You are the System 1 engine of a Neurosymbolic Lisp Machine.") (cascade nil))
  (let ((backends (or cascade *provider-cascade*)))
    (dolist (backend backends)
      (let ((backend-fn (gethash backend *neuro-backends*)))
        (when backend-fn
          (kernel-log "SYSTEM 1: Attempting backend ~a..." backend)
          (let ((result (funcall backend-fn prompt system-prompt)))
            (if (and (stringp result) (search ":LOG" result) (search "Failure" result))
                (kernel-log "SYSTEM 1: Backend ~a failed. Falling back..." backend)
                (return-from ask-neuro result))))))
    "(:type :LOG :payload (:text \"Neural Cascade Failure\"))"))

(defun execute-gemini-request (prompt system-prompt)
  (let* ((auth (get-provider-auth :gemini)) (api-key (getf auth :api-key)) (bearer-token (getf auth :bearer-token))
         (endpoint (or (getf auth :endpoint) "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")))
    (unless (or api-key bearer-token) (return-from execute-gemini-request "(:type :LOG :payload (:text \"Authentication missing\"))"))
    (let* ((url (if api-key (format nil "~a?key=~a" endpoint api-key) endpoint))
           (headers `(("Content-Type" . "application/json") ,@(when bearer-token `(("Authorization" . ,(format nil "Bearer ~a" bearer-token))))))
           (body (cl-json:encode-json-to-string `((contents . ((parts . ((text . ,(format nil "~a~%~%Prompt: ~a" system-prompt prompt))))))))))
      (handler-case (let* ((response (dex:post url :headers headers :content body :connect-timeout 10 :read-timeout 30)) (json (cl-json:decode-json-from-string response)))
                      (cdr (assoc :text (cdr (assoc :parts (car (cdr (assoc :parts (car (cdr (assoc :candidates json)))))))))))
        (error (c) (format nil "(:type :LOG :payload (:text \"Neural Engine Failure: ~a\"))" c))))))

(defun execute-openrouter-request (prompt system-prompt)
  (let ((api-key (uiop:getenv "OPENROUTER_API_KEY"))
        (endpoint "https://openrouter.ai/api/v1/chat/completions")
        (model "google/gemini-flash-1.5")) ; default fallback
    ;; Dynamically read user's preferred model from the Object Store
    (maphash (lambda (id obj)
               (declare (ignore id))
               (let ((val (getf (org-object-attributes obj) :LLM_MODEL_OPENROUTER)))
                 (when val (setf model val))))
             *object-store*)
    (unless api-key (return-from execute-openrouter-request "(:type :LOG :payload (:text \"OpenRouter API Key missing\"))"))
    (let* ((headers `(("Content-Type" . "application/json")
                      ("Authorization" . ,(format nil "Bearer ~a" api-key))
                      ("HTTP-Referer" . "https://github.com/amr/org-agent")))
           (body (cl-json:encode-json-to-string
                  `((model . ,model)
                    (messages . (( (role . "system") (content . ,system-prompt) )
                                 ( (role . "user") (content . ,prompt) )))))))
      (handler-case (let* ((response (dex:post endpoint :headers headers :content body :connect-timeout 10 :read-timeout 30))
                           (json (cl-json:decode-json-from-string response)))
                      (cdr (assoc :content (cdr (assoc :message (car (cdr (assoc :choices json))))))))
        (error (c) (format nil "(:type :LOG :payload (:text \"OpenRouter Failure: ~a\"))" c))))))

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
                (let* ((thought (ask-neuro prompt))
                       ;; Strip markdown code blocks
                       (cleaned-thought (cl-ppcre:regex-replace-all "(?s)^```(?:lisp)?\\n?(.*?)\\n?```$" (string-trim '(#\Space #\Newline #\Tab) thought) "\\1"))
                       (suggestion (ignore-errors (read-from-string cleaned-thought))))
                  (kernel-log "SYSTEM 1 Suggestion: ~a~%" cleaned-thought)
                  (cond
                    ((and suggestion (listp suggestion)) suggestion)
                    ;; SALVAGE: If LLM returned plain text or a non-list symbol
                    ((and (let ((p (getf context :payload))) (eq (getf p :sensor) :chat-message))
                          (> (length cleaned-thought) 0))
                     (kernel-log "SYSTEM 1: SALVAGING plain-text response.~%")
                     ;; Heuristic: If it looks like meta-commentary with quoted text, extract the quote
                     (let* ((quote-match (cl-ppcre:scan-to-strings "\"((?:\\\\.|[^\"\\\\])*)\"" cleaned-thought))
                            (payload-text (if (and quote-match (> (length quote-match) 0)) 
                                              (elt (nth-value 1 (cl-ppcre:scan-to-strings "\"((?:\\\\.|[^\"\\\\])*)\"" cleaned-thought)) 0)
                                              cleaned-thought)))
                       `(:type :request :target :emacs :payload (:action :insert-at-end :buffer "*org-agent-chat*" :text ,payload-text))))
                    (t (kernel-log "SYSTEM 1 ERROR: Could not parse response as Lisp plist.~%") nil)))
                '(:type :LOG :payload (:text "Skill triggered (Deterministic only)")))))
        nil)))

(defun distill-prompt (full-prompt successful-output)
  (let ((system-instr "You are a Meta-Cognitive Prompt Architect. DISTILL into template."))
    (ask-neuro (format nil "PROMPT: ~a~%RESULT: ~a" full-prompt successful-output) :system-prompt system-instr)))

(defun distillation-loop ()
  "Autonomous distillation cycle (Skeletal)."
  (kernel-log "NEURO [Evolution] - Distillation cycle triggered."))
