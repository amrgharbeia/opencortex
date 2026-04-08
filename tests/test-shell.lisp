(require :usocket)

(defun test-shell-execution ()
  (let* ((socket (usocket:socket-connect "127.0.0.1" 9105))
         (stream (usocket:socket-stream socket))
         ;; We send a chat message asking to run date
         (msg "(:type :event :payload (:sensor :chat-message :text \"run date\"))")
         (len (length msg))
         (framed (format nil "~6,'0x~a" len msg)))
    (format t "Sending request: ~a~%" msg)
    (write-string framed stream)
    (finish-output stream)
    (format t "Waiting for Shell Actuator response...~%")
    (handler-case
        (loop
          (let* ((len-prefix (make-string 6)))
            (read-sequence len-prefix stream)
            (let* ((msg-len (parse-integer len-prefix :radix 16))
                   (payload (make-string msg-len)))
              (read-sequence payload stream)
              (format t "AGENT REPLY: ~a~%" payload)
              ;; We look for the Shell Command Result headline in the response
              (when (search "Shell Command Result" payload)
                (format t "SUCCESS: Shell output received!~%")
                (return)))))
      (error (c) (format t "ERROR: ~a~%" c)))
    (usocket:socket-close socket)))

(test-shell-execution)
