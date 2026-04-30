(in-package :opencortex)

(defun execute-llm-request (&key prompt system-prompt (provider :ollama) model)
  "Central dispatcher for LLM requests."
  (let ((backend (gethash provider *probabilistic-backends*)))
    (if backend
        (handler-case
            (funcall backend prompt system-prompt :model model)
          (error (c)
            (list :status :error :message (format nil "~a Failure: ~a" provider c))))
        (list :status :error :message (format nil "Provider ~a not registered" provider)))))

(defskill :skill-llm-gateway
  :priority 100
  :trigger (lambda (ctx) (getf ctx :user-input))
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))
