(in-package :org-agent)

(defvar *matrix-since-token* nil)

(defvar *matrix-polling-thread* nil)

(defun get-matrix-homeserver () (vault-get-secret :matrix-homeserver))

(defun get-matrix-token () (vault-get-secret :matrix-token))

(defun execute-matrix-action (action context)
  "Sends a message via Matrix Client API."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (room-id (or (getf payload :room-id) (getf action :room-id)))
         (text (or (getf payload :text) (getf action :text)))
         (hs (get-matrix-homeserver))
         (token (get-matrix-token))
         (txn-id (get-universal-time))
         (url (format nil "~a/_matrix/client/v3/rooms/~a/send/m.room.message/~a" hs room-id txn-id)))
    (when (and hs token room-id text)
      (kernel-log "MATRIX: Sending message to ~a..." room-id)
      (handler-case 
          (dex:put url 
                   :headers `(("Authorization" . ,(format nil "Bearer ~a" token))
                              ("Content-Type" . "application/json"))
                   :content (cl-json:encode-json-to-string 
                             `((msgtype . "m.text") (body . ,text))))
        (error (c) (kernel-log "MATRIX ERROR: ~a" c))))))

(defun matrix-process-sync ()
  "Calls Matrix sync and injects new messages."
  (let* ((hs (get-matrix-homeserver))
         (token (get-matrix-token))
         (url (format nil "~a/_matrix/client/v3/sync?timeout=30000~@[&since=~a~]" 
                      hs *matrix-since-token*)))
    (when (and hs token)
      (handler-case
          (let* ((response (dex:get url :headers `(("Authorization" . ,(format nil "Bearer ~a" token)))))
               (json (cl-json:decode-json-from-string response))
               (next-batch (or (cdr (assoc :next-batch json))
                               (cdr (assoc :next--batch json))))
               (rooms (cdr (assoc :rooms json)))
               (joined (cdr (assoc :join rooms))))

          (when next-batch
            (setf *matrix-since-token* next-batch))

          (dolist (room-entry joined)
            (let* ((room-id (string-downcase (string (car room-entry))))
                   (room-data (cdr room-entry))
                   (timeline (cdr (assoc :timeline room-data)))
                   (events (cdr (assoc :events timeline))))
              (dolist (event events)
                (let* ((type (cdr (assoc :type event)))
                       (content (cdr (assoc :content event)))
                       (sender (cdr (assoc :sender event)))
                       (body (cdr (assoc :body content))))
                  (when (and (string= type "m.room.message") body)
                    (kernel-log "MATRIX: Received message from ~a in ~a" sender room-id)
                    (inject-stimulus 
                     (list :type :EVENT 
                           :payload (list :sensor :chat-message 
                                          :channel :matrix 
                                          :room-id room-id 
                                          :sender sender 
                                          :text body)))))))))        (error (c) (kernel-log "MATRIX SYNC ERROR: ~a" c))))))

(defun start-matrix-gateway ()
  "Initializes the Matrix background thread."
  (unless (and *matrix-polling-thread* (bt:thread-alive-p *matrix-polling-thread*))
    (setf *matrix-polling-thread*
          (bt:make-thread 
           (lambda ()
             (loop
               (matrix-process-sync)
               (sleep 2)))
           :name "org-agent-matrix-gateway"))
    (kernel-log "MATRIX: Gateway sync active.")))

(defun stop-matrix-gateway ()
  (when (and *matrix-polling-thread* (bt:thread-alive-p *matrix-polling-thread*))
    (bt:destroy-thread *matrix-polling-thread*)
    (setf *matrix-polling-thread* nil)))

(register-actuator :matrix #'execute-matrix-action)

(defskill :skill-gateway-matrix
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) nil)
  :neuro nil
  :symbolic (lambda (action ctx) (declare (ignore ctx)) action))

(start-matrix-gateway)
