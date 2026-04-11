(in-package :org-agent)

(defvar *actuator-registry* (make-hash-table :test 'equal)
  "Global registry mapping target keywords to their physical actuator functions.")

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive two arguments: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun frame-message (msg-string)
  "Prefix MSG-STRING with a 6-character hex length (lowercase).
   FUTURE: Will also prefix a 64-char HMAC signature when OACP_ENFORCE_HMAC=true."
  (let ((len (length msg-string))
        (enforce-hmac (uiop:getenv "OACP_ENFORCE_HMAC")))
    (if (and enforce-hmac (string-equal enforce-hmac "true"))
        (let* ((secret (or (uiop:getenv "OACP_HMAC_SECRET") "default-insecure-secret"))
               (key (ironclad:ascii-string-to-byte-array secret))
               (hmac (ironclad:make-mac :hmac key :sha256))
               (payload-bytes (ironclad:ascii-string-to-byte-array msg-string)))
          (ironclad:update-mac hmac payload-bytes)
          (let ((signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
            (format nil "~(~6,'0x~)~a~a" len signature msg-string)))
        (format nil "~(~6,'0x~)~a" len msg-string))))

(defun parse-message (framed-string)
  "Extract and parse the S-expression from a framed string, securely preventing reader macro injection."
  (when (< (length framed-string) 6)
    (error "Framed string too short"))
  (let* ((enforce-hmac (uiop:getenv "OACP_ENFORCE_HMAC"))
         (use-hmac (and enforce-hmac (string-equal enforce-hmac "true")))
         (prefix-len (if use-hmac 70 6)))
    (when (< (length framed-string) prefix-len)
      (error "Framed string too short for OACP signature/length"))
    
    (let* ((len-str (subseq framed-string 0 6))
           (signature (when use-hmac (subseq framed-string 6 70)))
           (actual-msg (subseq framed-string prefix-len))
           (expected-len (ignore-errors (parse-integer len-str :radix 16))))
      (unless expected-len
        (error "Invalid hex length prefix: ~a" len-str))
      (unless (= expected-len (length actual-msg))
        (error "Message length mismatch. Expected ~a, got ~a" expected-len (length actual-msg)))
      
      ;; HMAC Validation Foundation
      (when use-hmac
        (let* ((secret (or (uiop:getenv "OACP_HMAC_SECRET") "default-insecure-secret"))
               (key (ironclad:ascii-string-to-byte-array secret))
               (hmac (ironclad:make-mac :hmac key :sha256))
               (payload-bytes (ironclad:ascii-string-to-byte-array actual-msg)))
          (ironclad:update-mac hmac payload-bytes)
          (let ((expected-signature (ironclad:byte-array-to-hex-string (ironclad:produce-mac hmac))))
            (unless (string-equal signature expected-signature)
              (error "OACP Integrity Failure: HMAC signature mismatch")))))
      
      ;; SECURITY: Prevent Reader Macro Injection (e.g. #. ) during deserialization
      (let ((*read-eval* nil))
        (read-from-string actual-msg)))))

(defun make-hello-message (version)
  "Construct the standard HELLO handshake message."
  (list :type :EVENT 
        :payload (list :action :handshake 
                       :version version 
                       :capabilities '(:auth :swank :org-ast))))
