(in-package :opencortex)

(defun llama-inference (prompt system-prompt &key (model "local-model"))
  "Sends a completion request to the local llama.cpp server."
  (let ((endpoint (uiop:getenv "LLAMACPP_ENDPOINT")))
    (unless endpoint
      (harness-log "LLAMA ERROR: LLAMACPP_ENDPOINT not set in environment.")
      (return-from llama-inference (list :error "LLAMACPP_ENDPOINT_MISSING")))

    (handler-case
        (let* ((full-prompt (format nil "System: ~a~%User: ~a~%Assistant:" system-prompt prompt))
               (payload (cl-json:encode-json-to-string 
                         `((:prompt . ,full-prompt)
                           (:n_predict . 1024)
                           (:stop . ("User:" "System:")))))
               (response (dex:post (format nil "~a/completion" endpoint)
                                   :content payload
                                   :headers '(("Content-Type" . "application/json"))))
               (data (cl-json:decode-json-from-string response)))
          (cdr (assoc :content data)))
      (error (c)
        (harness-log "LLAMA ERROR: Connection failed -> ~a" c)
        (list :error (format nil "~a" c))))))

(progn
  (register-probabilistic-backend :llama #'llama-inference)
  (harness-log "LLAMA: Local backend registered and active."))

(defskill :skill-llama-backend
  :priority 50
  :trigger (lambda (ctx) (declare (ignore ctx)) nil) ; Pure infrastructure skill
  :probabilistic nil
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))
