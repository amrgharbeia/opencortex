(in-package :org-agent)

(defun get-signal-account () (vault-get-secret :signal))

(defvar *signal-polling-thread* nil)

(defun execute-signal-action (action context)
  "Sends a message via signal-cli."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (chat-id (or (getf payload :chat-id) (getf action :chat-id)))
         (text (or (getf payload :text) (getf action :text)))
         (account (get-signal-account)))
    (when (and account chat-id text)
      (harness-log "SIGNAL: Sending message to ~a..." chat-id)
      (handler-case 
          (uiop:run-program (list "signal-cli" "-u" account "send" "-m" text chat-id)
                            :output :string :error-output :string)
        (error (c) (harness-log "SIGNAL ERROR: ~a" c))))))

(defun signal-process-updates ()
  "Polls for new messages via signal-cli and injects them into the harness."
  (let ((account (get-signal-account)))
    (when account
      (handler-case
          (let* ((output (uiop:run-program (list "signal-cli" "-u" account "receive" "--json")
                                           :output :string :error-output :string :ignore-error-status t))
                 (lines (cl-ppcre:split "\\n" output)))
            (dolist (line lines)
              (when (and line (> (length line) 0))
                (let* ((json (ignore-errors (cl-json:decode-json-from-string line)))
                       (envelope (cdr (assoc :envelope json)))
                       (source (cdr (assoc :source envelope)))
                       (data-message (cdr (assoc :data-message envelope)))
                       (text (cdr (assoc :message data-message))))
                  (when (and source text)
                    (harness-log "SIGNAL: Received message from ~a" source)
                    (inject-stimulus 
                     (list :type :EVENT 
                           :payload (list :sensor :chat-message 
                                          :channel :signal 
                                          :chat-id source 
                                          :text text))))))))
        (error (c) (harness-log "SIGNAL POLL ERROR: ~a" c))))))

(defun start-signal-gateway ()
  "Initializes the Signal background thread."
  (unless (and *signal-polling-thread* (bt:thread-alive-p *signal-polling-thread*))
    (setf *signal-polling-thread*
          (bt:make-thread 
           (lambda ()
             (loop
               (signal-process-updates)
               (sleep 5)))
           :name "org-agent-signal-gateway"))
    (harness-log "SIGNAL: Gateway polling active.")))

(defun stop-signal-gateway ()
  (when (and *signal-polling-thread* (bt:thread-alive-p *signal-polling-thread*))
    (bt:destroy-thread *signal-polling-thread*)
    (setf *signal-polling-thread* nil)))

(register-actuator :signal #'execute-signal-action)

(defskill :skill-gateway-signal
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) nil) ;; Passive
  :probabilistic nil
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))

(start-signal-gateway)
