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

(defvar *model-selector-fn* nil "A function called with (provider context) to return a model ID.")

(defun ask-neuro (prompt &key (system-prompt "You are the System 1 engine of a Neurosymbolic Lisp Machine.") (cascade nil) (context nil))
  "Dispatches a neural request through the provider cascade.
   If CASCADE is a function, it is called with CONTEXT to determine backends."
  (let ((backends (cond
                    ((and cascade (listp cascade)) cascade)
                    ((functionp cascade) (funcall cascade context))
                    (t *provider-cascade*))))
    (dolist (backend backends)
      (let ((backend-fn (gethash backend *neuro-backends*)))
        (when backend-fn
          (kernel-log "SYSTEM 1: Attempting backend ~a..." backend)
          (let* (;; Consult the model selector (e.g. economist) for the model ID if available
                 (model (when *model-selector-fn* (funcall *model-selector-fn* backend context)))
                 (result (if model 
                             (funcall backend-fn prompt system-prompt :model model)
                             (funcall backend-fn prompt system-prompt))))
            (if (and (stringp result) (search ":LOG" result) (or (search "Failure" result) (search "missing" result)))
                (kernel-log "SYSTEM 1: Backend ~a failed. Falling back..." backend)
                (return-from ask-neuro result))))))
    "(:type :LOG :payload (:text \"Neural Cascade Failure\"))"))

;; --- Sovereign Service Fallbacks ---

(defun economist-route-task (context)
  "Generic fallback for routing. Overridden by skill-economist."
  (declare (ignore context))
  '(:openrouter :gemini))

(defun org-id-new ()
  "Generic fallback for ID generation. Overridden by skill-ast-normalization."
  (format nil "node-~a" (get-universal-time)))

(defun get-org-timestamp ()
  "Returns a current Org-mode active timestamp."
  (multiple-value-bind (sec min hour day month year day-of-week) (decode-universal-time (get-universal-time))
    (declare (ignore sec))
    (let ((day-names '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))
      (format nil "[~4,'0d-~2,'0d-~2,'0d ~a ~2,'0d:~2,'0d]" 
              year month day (nth day-of-week day-names) hour min))))

(defun update-note-metadata (filepath)
  "Ensures a :PROPERTIES: drawer exists and updates the :EDITED: timestamp."
  (let ((content (uiop:read-file-string filepath))
        (now (get-org-timestamp)))
    (if (search ":PROPERTIES:" content)
        ;; Update existing EDITED or add it
        (let ((new-content (if (search ":EDITED:" content)
                               (cl-ppcre:regex-replace ":EDITED:   \\[.*?\\]" content (format nil ":EDITED:   ~a" now))
                               (cl-ppcre:regex-replace ":PROPERTIES:\\n" content (format nil ":PROPERTIES:~%:EDITED:   ~a~%" now)))))
          (with-open-file (out filepath :direction :output :if-exists :supersede)
            (write-string new-content out)))
        ;; Create new drawer
        (let ((new-content (format nil ":PROPERTIES:~%:CREATED:  ~a~%:EDITED:   ~a~%:END:~%~a" now now content)))
          (with-open-file (out filepath :direction :output :if-exists :supersede)
            (write-string new-content out))))))

(defun think (context)
  (let ((active-skill (find-triggered-skill context))
        (tool-belt (generate-tool-belt-prompt)))
    (if active-skill
        (progn
          (kernel-log "SYSTEM 1: Engaging skill '~a'~%" (skill-name active-skill))
          (let* ((prompt-generator (skill-neuro-prompt active-skill)) 
                 (raw-prompt (when prompt-generator (funcall prompt-generator context)))
                 (full-system-prompt (concatenate 'string 
                                                 "ACTUATOR IDENTITY: You are the pure Lisp actuator for the org-agent kernel.
MANDATE: Output EXACTLY ONE Common Lisp property list starting with (:type :REQUEST).
ZERO CONVERSATION: Do not explain. Do not say 'Okay'. Do not use markdown blocks.
STRICT RULE: Do not output multiple lists. Do not chain multiple requests. 
DO NOT embed tool calls inside text strings.
If you need to do multiple things or need information from a tool, you MUST:
1. Call the tool FIRST.
2. Wait for the result in the next recursive turn.
3. Only then reply to the user or call the next tool.

"
                                                 tool-belt
                                                 "
IMPORTANT: To reply to the user, you MUST use:
(:type :REQUEST :target :emacs :action :insert-at-end :buffer \"*org-agent-chat*\" :text \"* <Response Text>\")

To call a tool, you MUST use:
(:type :REQUEST :target :tool :action :call :tool \"<name>\" :args (:arg1 \"val\"))

")))
            (if (and raw-prompt (> (length raw-prompt) 1))
                (let* ((thought (ask-neuro raw-prompt :system-prompt full-system-prompt :context context)))
                  (kernel-log "SYSTEM 1 RAW: ~a~%" thought)
                  (let* ((cleaned-thought 
                          (let ((match (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" thought)))
                            (if match
                                (let ((regs (nth-value 1 (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" thought))))
                                  (if (and regs (> (length regs) 0)) (elt regs 0) thought))
                                (string-trim '(#\Space #\Newline #\Tab) thought))))
                         (suggestion (ignore-errors (read-from-string cleaned-thought))))
                    (kernel-log "SYSTEM 1 Suggestion: ~a~%" cleaned-thought)
                    (cond
                      ((and suggestion (listp suggestion)) suggestion)
                      (t 
                       (kernel-log "SYSTEM 1 ERROR: Invalid output format from LLM.~%")
                       nil))))
                '(:type :LOG :payload (:text "Skill triggered (Deterministic only)")))))
        nil)))

(defun distill-prompt (full-prompt successful-output)
  (let ((system-instr "You are a Meta-Cognitive Prompt Architect. DISTILL into template."))
    (ask-neuro (format nil "PROMPT: ~a~%RESULT: ~a" full-prompt successful-output) :system-prompt system-instr)))

(defun distillation-loop ()
  "Autonomous distillation cycle (Skeletal)."
  (kernel-log "NEURO [Evolution] - Distillation cycle triggered."))
