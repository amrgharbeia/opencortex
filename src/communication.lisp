(in-package :opencortex)

(defvar *actuator-registry* (make-hash-table :test 'equalp)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (let ((key (if (keywordp name) name (intern (string-upcase (string name)) :keyword))))
    (setf (gethash key *actuator-registry*) fn)))

(defun frame-message (msg-plist)
  "Frames a Lisp plist with a 6-character hex length and a newline for stream integrity."
  (let* ((*print-pretty* nil)
         (*print-circle* nil)
         (msg-string (format nil "~s" msg-plist))
         (len (length msg-string)))
    (format nil "~6,'0x~a~%" len msg-string)))

(defun read-framed-message (stream)
  "Reads a hex-length prefixed S-expression from the stream securely. Skips leading whitespace."
  (let ((length-buffer (make-string 6)))
    (handler-case
        (progn
          ;; 1. Skip leading whitespace (newlines, spaces, etc.)
          (loop for char = (peek-char nil stream nil :eof)
                while (and (not (eq char :eof)) (member char '(#\Space #\Newline #\Tab #\Return)))
                do (read-char stream))
          
          ;; 2. Read the 6-char hex length
          (let ((count (read-sequence length-buffer stream)))
            (cond ((< count 6) :eof)
                  (t (let ((len (ignore-errors (parse-integer length-buffer :radix 16))))
                       (if (not len)
                           (progn
                             (harness-log "PROTOCOL ERROR: Invalid header ~s. Attempting resync..." length-buffer)
                             :error)
                           (let ((msg-buffer (make-string len)))
                             (read-sequence msg-buffer stream)
                             (let ((*read-eval* nil)
                                   (*print-pretty* nil))
                               (handler-case 
                                   (let ((msg (read-from-string msg-buffer)))
                                     (validate-communication-protocol-schema msg)
                                     msg)
                                 (error (c)
                                   (harness-log "PROTOCOL PARSE ERROR: ~a in ~s" c msg-buffer)
                                   :error))))))))))
      (error (c) 
        (harness-log "PROTOCOL READ ERROR: ~a" c)
        :error))))

(defun make-hello-message (version)
  "Constructs the standard HELLO handshake message."
  (list :TYPE :EVENT 
        :PAYLOAD (list :ACTION :handshake 
                       :VERSION version 
                       :CAPABILITIES '(:AUTH :SWANK :ORG-AST))))

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
