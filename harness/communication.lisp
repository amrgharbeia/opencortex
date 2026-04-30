(in-package :opencortex)

(defvar *actuator-registry* (make-hash-table :test 'equalp)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (let ((key (if (keywordp name) name (intern (string-upcase (string name)) :keyword))))
    (setf (gethash key *actuator-registry*) fn)))

(defun sanitize-protocol-message (msg)
  "Recursively strips non-serializable objects from a protocol plist."
  (if (and msg (listp msg))
      (let ((clean nil))
        (loop for (k v) on msg by #'cddr
              do (unless (member k '(:reply-stream :socket :stream))
                   (push k clean)
                   (push (if (listp v) (sanitize-protocol-message v) v) clean)))
        (nreverse clean))
      msg))

(defun frame-message (msg)
  "Serializes a message plist and prefixes it with a 6-character hex length."
  (let* ((sanitized (sanitize-protocol-message msg))
         (payload (let ((*print-pretty* nil) (*read-eval* nil)) (format nil "~s" sanitized)))
         (len (length payload)))
    (format nil "~6,'0x~a" len payload)))

(defun read-framed-message (stream)
  "Reads a hex-length prefixed S-expression from the stream securely."
  (let ((length-buffer (make-string 6)))
    (handler-case
        (progn
          (loop for char = (peek-char nil stream nil :eof)
                while (and (not (eq char :eof)) (member char '(#\Space #\Newline #\Tab #\Return)))
                do (read-char stream))
          (let ((count (read-sequence length-buffer stream)))
            (if (< count 6)
                :eof
                (let ((len (ignore-errors (parse-integer length-buffer :radix 16))))
                  (if (not len)
                      :error
                      (let ((msg-buffer (make-string len)))
                        (read-sequence msg-buffer stream)
                        (let ((*read-eval* nil))
                          (handler-case (read-from-string msg-buffer)
                            (error () :error)))))))))
      (error () :error))))

(defvar *server-socket* nil)

(defun handle-client-connection (socket)
  "Handles a single TUI/CLI client connection in a dedicated thread."
  (let ((stream (usocket:socket-stream socket)))
    (handler-case
        (progn
          (format stream "~a" (frame-message (make-hello-message "0.2.0")))
          (finish-output stream)
          (loop
            (let ((msg (read-framed-message stream)))
              (cond
                ((eq msg :eof) (return))
                ((eq msg :error) (return))
                ((eq (getf msg :type) :health-check)
                 ;; Handle health check request
                 (let ((health-msg (list :type :health-response 
                                          :status (or (and (boundp 'opencortex::*system-health*) 
                                                          (symbol-value 'opencortex::*system-health*))
                                                      :unknown)
                                          :checked-p (or (and (boundp 'opencortex::*health-check-ran*)
                                                              (symbol-value 'opencortex::*health-check-ran*))
                                                      nil))))
                   (format stream "~a" (frame-message health-msg))
                   (finish-output stream)))
                (t (inject-stimulus msg :stream stream))))))
      (error (c) (harness-log "CLIENT ERROR: ~a" c)))
    (ignore-errors (usocket:socket-close socket))))

(defun start-daemon (&key (port 9105))
  "Starts the network listener for TUI/CLI clients."
  (setf *server-socket* (usocket:socket-listen "127.0.0.1" port :reuse-address t))
  (harness-log "DAEMON: Listening on localhost:~a" port)
  (bt:make-thread
   (lambda ()
     (loop
       (let ((client-socket (usocket:socket-accept *server-socket*)))
         (when client-socket
           (bt:make-thread (lambda () (handle-client-connection client-socket))
                          :name "opencortex-client-handler")))))
   :name "opencortex-server-listener"))

(defun make-hello-message (version)
  "Constructs the standard HELLO handshake message."
  (list :TYPE :EVENT 
        :PAYLOAD (list :ACTION :handshake 
                       :VERSION version 
                       :CAPABILITIES '(:AUTH :ORG-AST))))
