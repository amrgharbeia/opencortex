(in-package :opencortex)

(defun protocol-validate (msg)
  "Enforces structural schema compliance on protocol messages."
  (validate-communication-protocol-schema msg))

(defskill :skill-protocol-validator
  :priority 95
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :deterministic (lambda (action ctx)
                   (declare (ignore ctx))
                   (handler-case
                       (progn (protocol-validate action) action)
                     (error (c)
                       (list :type :LOG :payload (list :level :error :text (format nil "Protocol Violation: ~a" c)))))))
