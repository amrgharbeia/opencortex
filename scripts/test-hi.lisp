(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(ql:quickload :usocket :silent t)

(defun frame-message (msg)
  (let* ((payload (format nil "~s" msg))
         (len (length payload)))
    (format nil "~6,'0x~a" len payload)))

(defun test-hi ()
  (handler-case
      (let* ((socket (usocket:socket-connect "127.0.0.1" 9105))
             (stream (usocket:socket-stream socket)))
        (format t "Connected to daemon.~%")
        
        ;; Read HELLO
        (let* ((len-buf (make-string 6))
               (count (read-sequence len-buf stream)))
          (when (= count 6)
            (let* ((len (parse-integer len-buf :radix 16))
                   (msg-buf (make-string len)))
              (read-sequence msg-buf stream)
              (format t "Received HELLO: ~a~%" msg-buf))))
        
        ;; Send HI
        (let* ((msg '(:TYPE :EVENT :META (:SOURCE :tui) :PAYLOAD (:SENSOR :user-input :TEXT "hi")))
               (framed (frame-message msg)))
          (format stream "~a" framed)
          (finish-output stream)
          (format t "Sent HI.~%"))
        
        ;; Wait for response
        (loop
          (let* ((len-buf (make-string 6))
                 (count (read-sequence len-buf stream)))
            (if (= count 6)
                (let* ((len (parse-integer len-buf :radix 16))
                       (msg-buf (make-string len)))
                  (read-sequence msg-buf stream)
                  (format t "Received Response: ~a~%" msg-buf)
                  (return))
                (progn
                  (format t "Waiting...~%")
                  (sleep 1)))))
        (usocket:socket-close socket))
    (error (c) (format t "Error: ~a~%" c))))

(test-hi)
(uiop:quit 0)
