(in-package :opencortex)

(defun validate-communication-protocol-schema (msg)
  "Strict structural validation for incoming protocol messages."
  (unless (listp msg) (error "Message must be a plist"))
  (let ((type (proto-get msg :type)))
    (unless (member type '(:REQUEST :EVENT :RESPONSE :LOG :STATUS))
      (error "Invalid message type '~a'" type))
    t))
