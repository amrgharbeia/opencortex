(in-package :org-agent)

(defun get-nested (alist &rest keys)
  "Recursively extracts nested values from an alist, handling both objects and arrays."
  (let ((val alist))
    (dolist (k keys)
      ;; If val is an array (a list where the first element is a list but NOT a pair),
      ;; descend into the first element.
      (when (and (listp val) (listp (car val)) (not (keywordp (caar val))))
        (setf val (car val)))
      (let ((pair (assoc k val)))
        (if pair
            (setf val (cdr pair))
            (return-from get-nested nil))))
    val))

(defun execute-llm-request (prompt system-prompt &key provider model)
  "Unified entry point for all LLM providers."
  (let ((api-key (vault-get-secret provider :type :api-key))
        (full-prompt (format nil "~a~%~%Prompt: ~a" system-prompt prompt)))

    (kernel-log "SYSTEM 1: Requesting ~a (Model: ~a) [Key: ~a]" 
                provider (or model "default") (vault-mask-string api-key))

    (case provider
      (:gemini-web
       (let ((res (uiop:symbol-call :org-agent.skills.org-skill-web-research :ask-gemini-web full-prompt)))
         (if res (list :status :success :content res) (list :status :error :message "Web Research Failure"))))
      
      (:ollama
       (let* ((host (or (uiop:getenv "OLLAMA_HOST") "localhost:11434"))
              (url (format nil "http://~a/api/generate" host))
              (body (cl-json:encode-json-to-string `((model . ,(or model "llama3")) (prompt . ,full-prompt) (stream . :false)))))
         (handler-case 
             (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body :connect-timeout 5 :read-timeout 60))
                    (json (cl-json:decode-json-from-string response)))
               (list :status :success :content (cdr (assoc :response json))))
           (error (c) (list :status :error :message (format nil "Ollama Failure: ~a" c))))))

      (t ;; Cloud Providers (Anthropic, Gemini API, Groq, OpenAI, OpenRouter)
       (when (or (null api-key) (string= api-key ""))
         (return-from execute-llm-request (list :status :error :message (format nil "API Key missing for ~a" provider))))
       (let* ((endpoint (case provider
                          (:anthropic "https://api.anthropic.com/v1/messages")
                          (:gemini-api (format nil "https://generativelanguage.googleapis.com/v1/models/~a:generateContent" (or model "gemini-1.5-flash-latest")))
                          (:groq "https://api.groq.com/openai/v1/chat/completions")
                          (:openai "https://api.openai.com/v1/chat/completions")
                          (:openrouter "https://openrouter.ai/api/v1/chat/completions")))
              (headers (case provider
                         (:anthropic `(("Content-Type" . "application/json") ("x-api-key" . ,api-key) ("anthropic-version" . "2023-06-01")))
                         (:gemini-api `(("Content-Type" . "application/json") ("x-goog-api-key" . ,api-key)))
                         (:openrouter `(("Content-Type" . "application/json") ("Authorization" . ,(format nil "Bearer ~a" api-key)) 
                                        ("HTTP-Referer" . "https://github.com/amr/org-agent") ("X-Title" . "org-agent Sovereign Kernel")))
                         (t `(("Content-Type" . "application/json") ("Authorization" . ,(format nil "Bearer ~a" api-key))))))
              (body (case provider
                      (:anthropic (cl-json:encode-json-to-string `((model . ,(or model "claude-3-5-sonnet-20240620")) (max_tokens . 4096) (system . ,system-prompt) (messages . (( (role . "user") (content . ,prompt) ))))))
                      (:gemini-api (cl-json:encode-json-to-string `((contents . (((parts . (((text . ,full-prompt))))))))))
                      (t (cl-json:encode-json-to-string `((model . ,(or model (case provider (:groq "llama-3.3-70b-versatile") (:openai "gpt-4o") (t "openrouter/auto"))))
                                                         (messages . (( (role . "system") (content . ,system-prompt) ) ( (role . "user") (content . ,prompt) )))))))))
         (handler-case 
             (let* ((response (dex:post endpoint :headers headers :content body :connect-timeout 10 :read-timeout 30))
                    (json (cl-json:decode-json-from-string response)))
               (let ((content (case provider
                                (:anthropic (get-nested json :content :text))
                                (:gemini-api (get-nested json :candidates :parts :text))
                                (t (get-nested json :choices :message :content)))))
                 (if content
                     (list :status :success :content content)
                     (list :status :error :message (format nil "Failed to parse ~a response structure." provider)))))
           (error (c) (list :status :error :message (format nil "LLM Gateway Failure (~a): ~a" provider c)))))))))

(def-cognitive-tool :ask-llm "Queries an LLM provider via the unified gateway."
  :parameters ((:prompt :type :string :description "The user prompt.")
               (:system-prompt :type :string :description "The system instructions.")
               (:provider :type :keyword :description "The provider (e.g., :gemini-api, :anthropic, :groq, :openai, :openrouter, :ollama, :gemini-web).")
               (:model :type :string :description "Optional specific model ID."))
  :body (lambda (args)
          (execute-llm-request (getf args :prompt) 
                               (or (getf args :system-prompt) "You are a helpful assistant.")
                               :provider (getf args :provider)
                               :model (getf args :model))))

(progn
  ;; Register all supported backends with the kernel
  (dolist (p '(:anthropic :gemini-api :gemini-web :groq :ollama :openai :openrouter))
    (org-agent:register-neuro-backend p (lambda (prompt system-prompt &key model)
                                          (execute-llm-request prompt system-prompt :provider p :model model))))
  
  (defskill :skill-llm-gateway
    :priority 150 ; Higher than individual old skills
    :trigger (lambda (context) nil)
    :neuro (lambda (context) nil)
    :symbolic (lambda (action context) action)))
