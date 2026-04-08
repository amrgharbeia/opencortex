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

"
                                                 tool-belt
                                                 "
IMPORTANT: To reply to the user, you MUST use:
(:type :REQUEST :target :emacs :payload (:action :insert-at-end :buffer \"*org-agent-chat*\" :text \"* <Response Text>\"))

To call a tool, you MUST use:
(:type :REQUEST :target :tool :payload (:action :call :tool \"<name>\" :args (:arg1 \"val\")))
")))
            (if (and raw-prompt (> (length raw-prompt) 0))
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
