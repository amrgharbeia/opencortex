(in-package :org-agent)

(defvar *neuro-backends* (make-hash-table :test 'equal))

(defvar *provider-cascade* nil)

(defun register-neuro-backend (name fn) (setf (gethash name *neuro-backends*) fn))

(defvar *model-selector-fn* nil "A function called with (provider context) to return a model ID.")

(defvar *consensus-enabled-p* nil "If T, ask-neuro queries all backends in parallel.")

(defun ask-neuro (prompt &key (system-prompt "You are the Probabilistic engine of a Neurosymbolic Lisp Machine.") (cascade nil) (context nil))
  "Dispatches a neural request through the provider cascade or parallel consensus."
  (let ((backends (cond
                    ((and cascade (listp cascade)) cascade)
                    ((functionp cascade) (funcall cascade context))
                    (t *provider-cascade*))))
    (if *consensus-enabled-p*
        ;; PARALLEL CONSENSUS MODE
        (let ((results nil)
              (threads nil)
              (lock (bt:make-lock)))
          (dolist (backend backends)
            (let ((backend-fn (gethash backend *neuro-backends*)))
              (when backend-fn
                (push (bt:make-thread 
                       (lambda ()
                         (harness-log "PROBABILISTIC [Consensus]: Querying backend ~a..." backend)
                         (let* ((model (when *model-selector-fn* (funcall *model-selector-fn* backend context)))
                                (result (ignore-errors 
                                          (if model 
                                              (funcall backend-fn prompt system-prompt :model model)
                                              (funcall backend-fn prompt system-prompt)))))
                           (bt:with-lock-held (lock)
                             (push result results)))))
                      threads))))
          ;; Wait for all threads with a timeout (e.g., 30s)
          (let ((start-time (get-universal-time)))
            (loop while (and (< (length results) (length threads))
                             (< (- (get-universal-time) start-time) 30))
                  do (sleep 0.1)))
          ;; Return the list of raw results (filtering out nils or errors)
          (let ((valid-results (remove-if-not #'stringp results)))
            (if valid-results
                (format nil "~{~a~^|CONSENSUS-SEP|~}" valid-results)
                "(:type :LOG :payload (:text \"Neural Consensus Failure\"))")))
        
        ;; SEQUENTIAL CASCADE MODE
        (or (dolist (backend backends)
              (let ((backend-fn (gethash backend *neuro-backends*)))
                (when backend-fn
                  (harness-log "PROBABILISTIC: Attempting backend ~a..." backend)
                  (let* ((model (when *model-selector-fn* (funcall *model-selector-fn* backend context)))
                         (result (if model 
                                     (funcall backend-fn prompt system-prompt :model model)
                                     (funcall backend-fn prompt system-prompt))))
                    (unless (or (null result)
                                (and (stringp result) (search ":LOG" result) (or (search "Failure" result) (search "missing" result))))
                      (return result))))))
            "(:type :LOG :payload (:text \"Neural Cascade Failure\"))"))))

(defun think (context)
  "Invokes the neural Probabilistic engine to propose a Lisp action based on context."
  (let ((active-skill (find-triggered-skill context))
        (tool-belt (generate-tool-belt-prompt))
        (global-context (context-assemble-global-awareness)))
    (if active-skill
        (progn
          (harness-log "PROBABILISTIC: Engaging skill '~a'~%" (skill-name active-skill))
          (let* ((prompt-generator (skill-neuro-prompt active-skill)) 
                 (raw-prompt (when prompt-generator (funcall prompt-generator context)))
                 (full-system-prompt (concatenate 'string 
                                                 "ACTUATOR IDENTITY: You are the pure Lisp actuator for the org-agent kernel.
MANDATE: Output EXACTLY ONE Common Lisp property list starting with (:type :REQUEST).
ZERO CONVERSATION: Do not explain. Do not say 'Okay'. Do not use markdown blocks.
STRICT RULE: Do not output multiple lists. Do not chain multiple requests. 
DO NOT embed tool calls inside text strings.

"
                                                 global-context
                                                 "
"
                                                 tool-belt
                                                 "
IMPORTANT: To reply to the user, you MUST use:
(:type :REQUEST :target :emacs :action :insert-at-end :buffer \"*org-agent-chat*\" :text \"* <Response Text>\")

To call a tool, you MUST use:
(:type :REQUEST :target :tool :action :call :tool \"<name>\" :args (:arg1 \"val\"))

")))
            (if (and raw-prompt (> (length raw-prompt) 1))
                (let* ((thought (ask-neuro raw-prompt :system-prompt full-system-prompt :context context))
                       (raw-thoughts (cl-ppcre:split (cl-ppcre:quote-meta-chars "|CONSENSUS-SEP|") thought))
                       (suggestions nil))
                  (dolist (raw-thought raw-thoughts)
                    (harness-log "PROBABILISTIC RAW: ~a~%" raw-thought)
                    (let* ((cleaned-thought 
                            (let ((match (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" raw-thought)))
                              (if match
                                  (let ((regs (nth-value 1 (cl-ppcre:scan-to-strings "(?s)```(?:lisp)?\\n?(.*?)\\n?```" raw-thought))))
                                    (if (and regs (> (length regs) 0)) (elt regs 0) raw-thought))
                                  (string-trim '(#\Space #\Newline #\Tab) raw-thought))))
                           (suggestion (handler-case (read-from-string cleaned-thought)
                                         (error (c)
                                           ;; EMIT ASYNCHRONOUS REPAIR STIMULUS
                                           (list :type :EVENT :payload 
                                                 (list :sensor :syntax-error 
                                                       :code cleaned-thought 
                                                       :error (format nil "~a" c)))))))
                      (harness-log "PROBABILISTIC Suggestion: ~a~%" cleaned-thought)
                      (when (and suggestion (listp suggestion))
                        (push suggestion suggestions))))
                  (if (and *consensus-enabled-p* suggestions)
                      (nreverse suggestions)
                      (first (nreverse suggestions))))
                '(:type :LOG :payload (:text "Skill triggered (Deterministic only)")))))
        nil)))

(defun distill-prompt (full-prompt successful-output)
  (let ((system-instr "You are a Meta-Cognitive Prompt Architect. DISTILL into template."))
    (ask-neuro (format nil "PROMPT: ~a~%RESULT: ~a" full-prompt successful-output) :system-prompt system-instr)))
