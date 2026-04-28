(in-package :opencortex)

(defparameter *skill-llm-gateway*
  '(:name "llm-gateway"
    :description "Unified provider-agnostic LLM interface."
    :capabilities (:ask-llm :get-embedding)
    :type :probabilistic)
  "Skill metadata for the LLM Gateway.")

(defun execute-llm-request (&key prompt system-prompt provider model)
  "Generic executor for all LLM providers."
  (let* ((active-provider (or provider :ollama))
         (api-key (uiop:getenv (format nil "~:@(~a_API_KEY~)" active-provider)))
         (full-prompt (if system-prompt (format nil "~a~%~%~a" system-prompt prompt) prompt)))
    (case active-provider
      (:ollama
       (let* ((host (or (uiop:getenv "OLLAMA_HOST") "localhost:11434"))
              (url (format nil "http://~a/api/generate" host))
              (body (cl-json:encode-json-to-string `((model . ,(or model "llama3")) (prompt . ,full-prompt) (stream . :false)))))
         (handler-case 
             (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body))
                    (json (cl-json:decode-json-from-string response)))
               (list :status :success :content (cdr (assoc :response json))))
           (error (c) (list :status :error :message (format nil "Ollama Failure: ~a" c))))))
      (t (list :status :error :message "Provider not implemented")))))

(def-cognitive-tool :get-ollama-embedding 
  "Generates vector embeddings via Ollama API."
  ((:text :type :string :description "Text to embed."))
  :body (lambda (args)
          (let ((text (getf args :text)))
            (let* ((host (or (uiop:getenv "OLLAMA_HOST") "localhost:11434"))
                   (url (format nil "http://~a/api/embeddings" host))
                   (body (cl-json:encode-json-to-string `((model . "nomic-embed-text") (prompt . ,text)))))
              (handler-case
                  (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body))
                         (json (cl-json:decode-json-from-string response)))
                    (cdr (assoc :embedding json)))
                (error (c) (harness-log "OLLAMA EMBED ERROR: ~a" c) nil))))))

(def-cognitive-tool :ask-llm 
  "Unified interface for interacting with LLM providers."
  ((:prompt :type :string :description "The user prompt")
   (:system-prompt :type :string :description "The system prompt (optional)")
   (:provider :type :keyword :description "The provider (e.g., :ollama, :openai)")
   (:model :type :string :description "The model name"))
  :body (lambda (args)
          (execute-llm-request :prompt (getf args :prompt)
                               :system-prompt (getf args :system-prompt)
                               :provider (getf args :provider)
                               :model (getf args :model))))

(defskill :skill-llm-gateway
  :priority 50
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :probabilistic (lambda (ctx) 
                  (let ((input (getf ctx :user-input)))
                    (when input
                      (execute-llm-request :prompt input))))
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))
