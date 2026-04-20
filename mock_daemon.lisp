(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(push (truename "./") asdf:*central-registry*)
(ql:quickload '(:usocket :bordeaux-threads :opencortex))

(defun handle-client (stream)
  (handler-case
      (progn
        (format stream "~a" (opencortex:frame-message (opencortex:make-hello-message "0.1.0")))
        (finish-output stream)
        (loop
          (let ((msg (opencortex:read-framed-message stream)))
            (when (or (eq msg :eof) (eq msg :error)) (return))
            (let ((text (getf (getf msg :payload) :text)))
              (format t "MOCK: Received ~s~%" text)
              (let ((resp (list :TYPE :REQUEST :PAYLOAD (list :ACTION :MESSAGE :TEXT (format nil "ECHO: ~a" text)))))
                (format stream "~a" (opencortex:frame-message resp))
                (finish-output stream))))))
    (error (c) (format t "MOCK ERROR: ~a~%" c))))

(let ((socket (usocket:socket-listen "127.0.0.1" 9105 :reuse-address t)))
  (format t "MOCK DAEMON LIVE ON 9105~%")
  (unwind-protect
       (loop (let ((client (usocket:socket-accept socket)))
               (bt:make-thread (lambda () 
                                 (unwind-protect 
                                      (handle-client (usocket:socket-stream client))
                                   (usocket:socket-close client))))))
    (usocket:socket-close socket)))
