(in-package :org-agent)

(defun trigger-skill-chat (context)
  (let* ((payload (getf context :payload))
         (sensor (getf payload :sensor)))
    (eq sensor :chat-message)))

(defun verify-skill-chat (proposed-action context)
  (let* ((payload (getf proposed-action :payload))
         (action (or (getf payload :action) (getf proposed-action :action)))
         (target (getf proposed-action :target)))
    (if (and (listp proposed-action)
             (or (and (member (getf proposed-action :type) '(:request :REQUEST))
                      (or (and (member target '(:emacs :EMACS))
                               (member action '(:insert-at-end :INSERT-AT-END)))
                          (and (member target '(:telegram :TELEGRAM))
                               (or (getf payload :chat-id) (getf proposed-action :chat-id)))
                          (and (member target '(:signal :SIGNAL))
                               (or (getf payload :chat-id) (getf proposed-action :chat-id)))
                          (and (member target '(:shell :SHELL))
                               (or (getf payload :cmd) (getf proposed-action :cmd)))
                          (member target '(:tool :TOOL))))
                 (member (getf proposed-action :type) '(:response :RESPONSE :log :LOG))))
        proposed-action
        (let ((err-text (format nil "
*System Error:* Chat agent returned invalid action: ~s" proposed-action)))
          `(:type :request :target :emacs :payload (:action :insert-at-end :buffer "*org-agent-chat*" :text ,err-text))))))

(defun neuro-skill-chat (context)
  "Generates a conversational response, stripping system errors from context."
  (let* ((payload (getf context :payload))
         (raw-text (getf payload :text))
         (channel (or (getf payload :channel) :emacs))
         (chat-id (getf payload :chat-id))
         ;; Context Purge: Remove system errors and hallucinations from the history
         (clean-text (cl-ppcre:regex-replace-all "(?i)Unknown request|System Error.*|Thinking\\.\\.\\." raw-text ""))
         (trimmed-text (if (> (length clean-text) 1000) 
                           (subseq clean-text (- (length clean-text) 1000)) 
                           clean-text))
         (reply-instruction 
          (case channel
            (:telegram (format nil "- To reply via Telegram: (:type :REQUEST :target :telegram :chat-id \"~a\" :text \"<Response>\")" chat-id))
            (:signal (format nil "- To reply via Signal: (:type :REQUEST :target :signal :chat-id \"~a\" :text \"<Response>\")" chat-id))
            (t "- To reply via Emacs: (:type :REQUEST :target :emacs :action :insert-at-end :buffer \"*org-agent-chat*\" :text \"* <Response>\")"))))
    (ask-neuro trimmed-text :system-prompt (concatenate 'string 
                                                       "ACTUATOR IDENTITY: You are the pure Lisp actuator for the org-agent kernel.
MANDATE: Output EXACTLY ONE Common Lisp property list starting with (:type :REQUEST).
ZERO CONVERSATION: Do not explain. Do not use markdown.
STRICT RULE: Never output the strings 'Unknown request' or 'System Error'. 

REQUIRED FORMATS:
" reply-instruction "
- To use a tool: (:type :REQUEST :target :tool :action :call :tool \"<name>\" :args (...))"))))

(defskill :skill-chat
  :priority 100
  :trigger #'trigger-skill-chat
  :neuro #'neuro-skill-chat
  :symbolic #'verify-skill-chat)
