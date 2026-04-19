import re

path_gateway = 'skills/org-skill-llm-gateway.org'
with open(path_gateway, 'r') as f: c = f.read()

# 1. Update execute-llm-request to be cascade-aware
old_executor = r'\(defun execute-llm-request \(prompt system-prompt &key provider model\).*?\(error \(c\) \(list :status :error :message \(format nil "LLM Gateway Failure \(~a\): ~a" provider c\)\)\)\)\)\)\)\)\)\)'

new_executor = """(defun execute-llm-request (prompt system-prompt &key provider model)
  "Unified entry point for all LLM providers. Respects the global cascade."
  (let* ((active-provider (or provider (car opencortex::*provider-cascade*)))
         (api-key (vault-get-secret active-provider :type :api-key))
         (full-prompt (format nil "~a~%~%Prompt: ~a" system-prompt prompt)))

    (harness-log "PROBABILISTIC ENGINE: Requesting ~a (Model: ~a)" 
                active-provider (or model "default"))

    ;; If the specifically requested provider has no key, try falling back to the cascade
    (when (or (null api-key) (string= api-key ""))
       (harness-log "GATEWAY: Provider ~a has no key. Falling back to cascade." active-provider)
       (return-from execute-llm-request 
         (ask-probabilistic prompt :system-prompt system-prompt :context (list :payload (list :text prompt)))))

    (case active-provider
      (:gemini-web
       (let ((res (uiop:symbol-call :opencortex.skills.org-skill-web-research :ask-gemini-web full-prompt)))
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
       (let* ((endpoint (case active-provider
                          (:anthropic "https://api.anthropic.com/v1/messages")
                          (:gemini-api (format nil "https://generativelanguage.googleapis.com/v1/models/~a:generateContent" (or model "gemini-1.5-flash-latest")))
                          (:groq "https://api.groq.com/openai/v1/chat/completions")
                          (:openai "https://api.openai.com/v1/chat/completions")
                          (:openrouter "https://openrouter.ai/api/v1/chat/completions")))
              (headers (case active-provider
                         (:anthropic `(("Content-Type" . "application/json") ("x-api-key" . ,api-key) ("anthropic-version" . "2023-06-01")))
                         (:gemini-api `(("Content-Type" . "application/json") ("x-goog-api-key" . ,api-key)))
                         (:openrouter `(("Content-Type" . "application/json") ("Authorization" . ,(format nil "Bearer ~a" api-key)) 
                                        ("HTTP-Referer" . "https://github.com/amr/opencortex") ("X-Title" . "opencortex Autonomous Kernel")))
                         (t `(("Content-Type" . "application/json") ("Authorization" . ,(format nil "Bearer ~a" api-key))))))
              (body (case active-provider
                      (:anthropic (cl-json:encode-json-to-string `((model . ,(or model "claude-3-5-sonnet-20240620")) (max_tokens . 4096) (system . ,system-prompt) (messages . (( (role . "user") (content . ,prompt) ))))))
                      (:gemini-api (cl-json:encode-json-to-string `((contents . (((parts . (((text . ,full-prompt))))))))))
                      (t (cl-json:encode-json-to-string `((model . ,(or model (case active-provider (:groq "llama-3.3-70b-versatile") (:openai "gpt-4o") (t "openrouter/auto"))))
                                                         (messages . (( (role . "system") (content . ,system-prompt) ) ( (role . "user") (content . ,prompt) )))))))))
         (handler-case 
             (let* ((response (progn 
                                (harness-log "LLM DEBUG: Requesting ~a..." active-provider)
                                (dex:post endpoint :headers headers :content body :connect-timeout 10 :read-timeout 30)))
                    (json (cl-json:decode-json-from-string response)))
               (let ((content (case active-provider
                                (:anthropic (get-nested json :content :text))
                                (:gemini-api (get-nested json :candidates :parts :text))
                                (t (get-nested json :choices :message :content)))))
                 (if content
                     (list :status :success :content content)
                     (list :status :error :message (format nil "Failed to parse ~a response structure." active-provider)))))
           (error (c) (list :status :error :message (format nil "LLM Gateway Failure (~a): ~a" active-provider c)))))))))"""

c = re.sub(old_executor, new_executor, c, flags=re.DOTALL)
with open(path_gateway, 'w') as f: f.write(c)

print("Enabled Dynamic Provider Cascading.")
