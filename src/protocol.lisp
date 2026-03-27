(in-package :org-agent)

(defun frame-message (msg-string)
  "Prefix MSG-STRING with a 6-character hex length (lowercase)."
  (let ((len (length msg-string)))
    (format nil "~(~6,'0x~)~a" len msg-string)))

(defun parse-message (framed-string)
  "Extract and parse the S-expression from a framed string."
  (when (< (length framed-string) 6)
    (error "Framed string too short"))
  (let* ((len-str (subseq framed-string 0 6))
         (actual-msg (subseq framed-string 6))
         (expected-len (ignore-errors (parse-integer len-str :radix 16))))
    (unless expected-len
      (error "Invalid hex length prefix: ~a" len-str))
    (unless (= expected-len (length actual-msg))
      (error "Message length mismatch. Expected ~a, got ~a" expected-len (length actual-msg)))
    (read-from-string actual-msg)))

(defun make-hello-message (version)
  "Construct the standard HELLO handshake message."
  (list :type :EVENT 
        :payload (list :action :handshake 
                       :version version 
                       :capabilities '(:auth :swank :org-ast))))
