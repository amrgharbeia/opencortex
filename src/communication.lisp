(in-package :opencortex)

(defvar *actuator-registry* (make-hash-table :test 'equal)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun frame-message (msg-string)
  "Prefixes MSG-STRING with a 6-character hex length.
   If security is enabled, prefixes a 64-char HMAC-SHA256 signature."
  (let ((*print-pretty* nil) (len (length msg-string))
        (enforce-hmac (uiop:getenv "PROTOCOL_ENFORCE_HMAC")))
    (if (and enforce-hmac (string-equal enforce-hmac "true"))
        (let ((secret (uiop:getenv "PROTOCOL_HMAC_SECRET")))
          (unless secret (error "PROTOCOL_HMAC_SECRET is required when security is enabled."))
          (let* ((key (ironclad:ascii-string-to-byte-array secret))
                 (hmac (ironclad:make-mac :hmac key :sha256))
                 (payload-bytes (ironclad:ascii-string-to-byte-array msg-string)))
            (ironclad:update-mac hmac payload-bytes)
            (let ((signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
              (format nil "~(~6,'0x~)~a~a" len signature msg-string))))
        (format nil "~(~6,'0x~)~a" len msg-string))))

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
  "Reads a hex-length prefixed JSON message from the stream."
  (let ((length-buffer (make-string 6)))
    (handler-case
        (progn
          ;; Skip leading junk (newlines, etc.)
          (loop for char = (peek-char nil stream nil :eof)
                while (and (not (eq char :eof)) (not (digit-char-p char 16)))
                do (read-char stream))
          
          (let ((count (read-sequence length-buffer stream)))
            (if (< count 6) :eof
                (let ((len (ignore-errors (parse-integer length-buffer :radix 16))))
                  (if (not len) :error
                      (let ((msg-buffer (make-string len)))
                        (read-sequence msg-buffer stream)
                        (let ((msg (cl-json:decode-json-from-string msg-buffer)))
                          ;; Convert JSON alist back to plist for kernel compatibility
                          (let ((plist nil))
                            (dolist (pair msg)
                              (push (intern (string-upcase (string (car pair))) :keyword) plist)
                              (push (cdr pair) plist))
                            (let ((final (nreverse plist)))
                              (validate-communication-protocol-schema final)
                              final)))))))))
      (error (c) (harness-log "PROTOCOL ERROR: ~a" c) :error))))
