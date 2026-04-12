(in-package :org-agent)

(defvar *actuator-registry* (make-hash-table :test 'equal)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun frame-message (msg-string)
  "Prefixes MSG-STRING with a 6-character hex length.
   If security is enabled, prefixes a 64-char HMAC-SHA256 signature."
  (let ((len (length msg-string))
        (enforce-hmac (uiop:getenv "HARNESS_PROTOCOL_ENFORCE_HMAC")))
    (if (and enforce-hmac (string-equal enforce-hmac "true"))
        (let* ((secret (or (uiop:getenv "HARNESS_PROTOCOL_HMAC_SECRET") "default-insecure-key"))
               (key (ironclad:ascii-string-to-byte-array secret))
               (hmac (ironclad:make-mac :hmac key :sha256))
               (payload-bytes (ironclad:ascii-string-to-byte-array msg-string)))
          (ironclad:update-mac hmac payload-bytes)
          (let ((signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
            (format nil "~(~6,'0x~)~a~a" len signature msg-string)))
        (format nil "~(~6,'0x~)~a" len msg-string))))

(defun parse-message (framed-string)
  "Extracts and parses the S-expression from a framed string securely."
  (when (< (length framed-string) 6)
    (error "Framed string too short"))
  (let* ((enforce-hmac (uiop:getenv "HARNESS_PROTOCOL_ENFORCE_HMAC"))
         (use-hmac (and enforce-hmac (string-equal enforce-hmac "true")))
         (prefix-len (if use-hmac 70 6)))
    (when (< (length framed-string) prefix-len)
      (error "Framed string too short for Harness Protocol prefix"))
    
    (let* ((len-str (subseq framed-string 0 6))
           (signature (when use-hmac (subseq framed-string 6 70)))
           (actual-msg (subseq framed-string prefix-len))
           (expected-len (ignore-errors (parse-integer len-str :radix 16))))
      (unless expected-len
        (error "Invalid hex length prefix: ~a" len-str))
      (unless (= expected-len (length actual-msg))
        (error "Message length mismatch. Expected ~a, got ~a" expected-len (length actual-msg)))
      
      (when use-hmac
        (let* ((secret (or (uiop:getenv "HARNESS_PROTOCOL_HMAC_SECRET") "default-insecure-key"))
               (key (ironclad:ascii-string-to-byte-array secret))
               (hmac (ironclad:make-mac :hmac key :sha256))
               (payload-bytes (ironclad:ascii-string-to-byte-array actual-msg)))
          (ironclad:update-mac hmac payload-bytes)
          (let ((expected-signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
            (unless (string-equal signature expected-signature)
              (error "Harness Protocol Integrity Failure: HMAC mismatch")))))
      
      ;; SECURITY: Disable the reader's ability to execute code during parsing
      (let ((*read-eval* nil))
        (let ((msg (read-from-string actual-msg)))
          (validate-harness-protocol-schema msg)
          msg)))))

(defun make-hello-message (version)
  "Constructs the standard HELLO handshake message."
  (list :type :EVENT 
        :payload (list :action :handshake 
                       :version version 
                       :capabilities '(:auth :swank :org-ast))))
