(in-package :opencortex)

(defvar *actuator-registry* (make-hash-table :test 'equalp))

(defun register-actuator (name fn)
  (let ((key (if (keywordp name) name (intern (string-upcase (string name)) :keyword))))
    (setf (gethash key *actuator-registry*) fn)))

(defun frame-message (msg-plist)
  (let* ((*print-pretty* nil)
         (*print-circle* nil)
         (msg-string (format nil "~s" msg-plist))
         (len (length msg-string)))
    (format nil "~6,'0x~a~%" len msg-string)))

(defun read-framed-message (stream)
  (let ((length-buffer (make-string 6)))
    (handler-case
        (progn
          (loop for char = (peek-char nil stream nil :eof)
                while (and (not (eq char :eof)) (member char '(#\Space #\Newline #\Tab #\Return)))
                do (read-char stream))
          (let ((count (read-sequence length-buffer stream)))
            (if (< count 6) :eof
                (let ((len (ignore-errors (parse-integer length-buffer :radix 16))))
                  (if (not len) :error
                      (let ((msg-buffer (make-string len)))
                        (read-sequence msg-buffer stream)
                        (let ((*read-eval* nil) (*print-pretty* nil))
                          (handler-case 
                              (let ((msg (read-from-string msg-buffer)))
                                (validate-communication-protocol-schema msg)
                                msg)
                            (error (c) :error)))))))))
      (error (c) :error))))

(defun make-hello-message (version)
  (list :TYPE :EVENT :PAYLOAD (list :ACTION :handshake :VERSION version :CAPABILITIES '(:AUTH :SWANK :ORG-AST))))
