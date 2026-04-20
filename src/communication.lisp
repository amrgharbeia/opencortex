(in-package :opencortex)

(defvar *actuator-registry* (make-hash-table :test 'equal)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun frame-message (msg-plist)
  "Frames a Lisp plist with a 6-char hex length and a newline sentinel for stream integrity."
  (let* ((*print-pretty* nil)
         (msg-string (format nil "~s" msg-plist))
         (len (length msg-string)))
    (format nil "~6,'0x~a~%" len msg-string)))

(defun parse-message (framed-string)
  "Extracts and parses the S-expression from a framed string securely."
  (when (< (length framed-string) 6)
    (error "Framed string too short"))
  (let* ((enforce-hmac (uiop:getenv "PROTOCOL_ENFORCE_HMAC"))
         (use-hmac (and enforce-hmac (string-equal enforce-hmac "true")))
         (prefix-len (if use-hmac 70 6)))
    (when (< (length framed-string) prefix-len)
      (error "Framed string too short for communication protocol prefix"))
    
    (let* ((len-str (subseq framed-string 0 6))
           (signature (when use-hmac (subseq framed-string 6 70)))
           (actual-msg (subseq framed-string prefix-len))
           (expected-len (ignore-errors (parse-integer len-str :radix 16))))
      (unless expected-len
        (error "Invalid hex length prefix: ~a" len-str))
      (unless (= expected-len (length actual-msg))
        (error "Message length mismatch. Expected ~a, got ~a" expected-len (length actual-msg)))
      
      (when use-hmac
        (let ((secret (uiop:getenv "PROTOCOL_HMAC_SECRET")))
          (unless secret (error "PROTOCOL_HMAC_SECRET is required when security is enabled."))
          (let* ((key (ironclad:ascii-string-to-byte-array secret))
                 (hmac (ironclad:make-mac :hmac key :sha256))
                 (payload-bytes (ironclad:ascii-string-to-byte-array actual-msg)))
            (ironclad:update-mac hmac payload-bytes)
            (let ((expected-signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
              (unless (string-equal signature expected-signature)
                (error "communication protocol Integrity Failure: HMAC mismatch"))))))
      
      ;; SECURITY: Disable the reader's ability to execute code during parsing
      (let ((*read-eval* nil) (*print-pretty* nil))
        (let ((msg (read-from-string actual-msg)))
          (validate-communication-protocol-schema msg)
          msg)))))

(defun make-hello-message (version)
  "Constructs the standard HELLO handshake message."
  (list :type :EVENT 
        :payload (list :action :handshake 
                       :version version 
                       :capabilities '(:auth :swank :org-ast))))

(defun read-framed-message (stream)
  "Robustly reads a hex-framed S-expression, skipping leading whitespace and handling desync."
  (let ((length-buffer (make-string 6)))
    (handler-case
        (progn
          ;; 1. Skip leading junk until we find a hex digit (the start of a length prefix)
          (loop for char = (peek-char nil stream nil :eof)
                while (and (not (eq char :eof)) (not (digit-char-p char 16)))
                do (read-char stream))
          
          (let ((count (read-sequence length-buffer stream)))
            (if (< count 6) :eof
                (let ((len (ignore-errors (parse-integer length-buffer :radix 16))))
                  (if (not len) :error
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
                               :error)))))))))
      (error (c) (harness-log "PROTOCOL READ ERROR: ~a" c) :error))))
