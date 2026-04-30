(in-package :opencortex)

(defun ollama-call (prompt system-prompt &key (model "llama3"))
  "Sends a request to the local Ollama API."
  (let* ((host (or (uiop:getenv "OLLAMA_HOST") "localhost:11434"))
         (url (format nil "http://~a/api/generate" host))
         (payload (cl-json:encode-json-to-string 
                   `((model . ,model)
                     (prompt . ,prompt)
                     (system . ,system-prompt)
                     (stream . nil)))))
    (handler-case
        (let ((response (dex:post url :content payload :headers '(("Content-Type" . "application/json")))))
          (let ((data (cl-json:decode-json-from-string response)))
            (list :status :success :content (getf data :response))))
      (error (c)
        (list :status :error :message (format nil "Ollama Failure: ~a" c))))))

(register-probabilistic-backend :ollama #'ollama-call)

(defskill :skill-llama-backend
  :priority 50
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
