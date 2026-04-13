(in-package :org-agent)

(defvar *telegram-last-update-id* 0)

(defvar *telegram-polling-thread* nil)

(defvar *telegram-authorized-chats* nil 
  "List of chat IDs allowed to interact with the bot. Hydrated from environment.")

(defun get-telegram-token () (vault-get-secret :telegram))

(defun execute-telegram-action (action context)
  "Sends a message back to Telegram."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (chat-id (or (getf payload :chat-id) (getf action :chat-id)))
         (text (or (getf payload :text) (getf action :text)))
         (token (get-telegram-token))
         (url (format nil "https://api.telegram.org/bot~a/sendMessage" token)))
    (when (and token chat-id text)
      (harness-log "TELEGRAM: Sending message to ~a..." chat-id)
      (handler-case 
          (dex:post url 
                    :headers '(("Content-Type" . "application/json"))
                    :content (cl-json:encode-json-to-string 
                              `((chat_id . ,chat-id) (text . ,text))))
        (error (c) (harness-log "TELEGRAM ERROR: ~a" c))))))

(defun telegram-process-updates ()
  "Polls for new messages and injects them into the harness."
  (let* ((token (get-telegram-token))
         (url (format nil "https://api.telegram.org/bot~a/getUpdates?offset=~a" 
                      token (1+ *telegram-last-update-id*))))
    (when token
      (handler-case
          (let* ((response (dex:get url))
                 (json (cl-json:decode-json-from-string response))
                 (updates (cdr (assoc :result json))))
            (dolist (update updates)
              (let* ((update-id (cdr (assoc :update--id update)))
                     (message (cdr (assoc :message update)))
                     (chat (cdr (assoc :chat message)))
                     (chat-id (cdr (assoc :id chat)))
                     (text (cdr (assoc :text message))))
                (setf *telegram-last-update-id* update-id)
                (when (and text chat-id)
                  (harness-log "TELEGRAM: Received message from ~a" chat-id)
                  (inject-stimulus 
                   (list :type :EVENT 
                         :payload (list :sensor :chat-message 
                                        :channel :telegram 
                                        :chat-id (format nil "~a" chat-id)
                                        :text text)))))))
        (error (c) (harness-log "TELEGRAM POLL ERROR: ~a" c))))))

(defun start-telegram-gateway ()
  "Initializes the Telegram background thread."
  (unless (and *telegram-polling-thread* (bt:thread-alive-p *telegram-polling-thread*))
    (setf *telegram-polling-thread*
          (bt:make-thread 
           (lambda ()
             (loop
               (telegram-process-updates)
               (sleep 3)))
           :name "org-agent-telegram-gateway"))
    (harness-log "TELEGRAM: Gateway polling active.")))

(defun stop-telegram-gateway ()
  (when (and *telegram-polling-thread* (bt:thread-alive-p *telegram-polling-thread*))
    (bt:destroy-thread *telegram-polling-thread*)
    (setf *telegram-polling-thread* nil)))

(register-actuator :telegram #'execute-telegram-action)

(defskill :skill-gateway-telegram
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) nil) ;; Passive, handles its own loop
  :probabilistic nil
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))

(start-telegram-gateway)
