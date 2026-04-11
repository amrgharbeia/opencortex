(defpackage :org-agent-llm-gateway-tests
  (:use :cl :fiveam :org-agent)
  (:export #:llm-gateway-suite))
(in-package :org-agent-llm-gateway-tests)

(def-suite llm-gateway-suite :description "Tests for the Unified LLM Gateway.")
(in-suite llm-gateway-suite)

(defun mock-dex-post (expected-json)
  "Returns a lambda that can be used to mock dex:post."
  (lambda (url &key headers content connect-timeout read-timeout)
    (declare (ignore url headers content connect-timeout read-timeout))
    expected-json))

(test test-provider-anthropic
  "Verify Anthropic request formatting and response parsing."
  (let ((old-post (symbol-function 'dex:post))
        (mock-response "{\"content\": [{\"text\": \"Anthropic thought\"}]}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:post) (mock-dex-post mock-response))
           (setf (uiop:getenv "ANTHROPIC_API_KEY") "test-key")
           (let ((res (org-agent::execute-llm-request "prompt" "sys" :provider :anthropic)))
             (is (eq (getf res :status) :success))
             (is (equal "Anthropic thought" (getf res :content)))))
      (setf (symbol-function 'dex:post) old-post))))

(test test-provider-gemini
  "Verify Gemini request formatting and response parsing."
  (let ((old-post (symbol-function 'dex:post))
        (mock-response "{\"candidates\": [{\"parts\": [{\"text\": \"Gemini thought\"}]}]}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:post) (mock-dex-post mock-response))
           (setf (uiop:getenv "GEMINI_API_KEY") "test-key")
           (let ((res (org-agent::execute-llm-request "prompt" "sys" :provider :gemini-api)))
             (is (eq (getf res :status) :success))
             (is (equal "Gemini thought" (getf res :content)))))
      (setf (symbol-function 'dex:post) old-post))))

(test test-provider-openai-compat
  "Verify OpenAI-compatible (Groq, OpenAI, OpenRouter) response parsing."
  (let ((old-post (symbol-function 'dex:post))
        (mock-response "{\"choices\": [{\"message\": {\"content\": \"OpenAI thought\"}}]}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:post) (mock-dex-post mock-response))
           (dolist (p '(:openai :groq :openrouter))
             (setf (uiop:getenv (format nil "~a_API_KEY" (string-upcase (string p)))) "test-key")
             (let ((res (org-agent::execute-llm-request "prompt" "sys" :provider p)))
               (is (eq (getf res :status) :success))
               (is (equal "OpenAI thought" (getf res :content))))))
      (setf (symbol-function 'dex:post) old-post))))

(test test-provider-ollama
  "Verify Ollama response parsing."
  (let ((old-post (symbol-function 'dex:post))
        (mock-response "{\"response\": \"Ollama thought\"}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:post) (mock-dex-post mock-response))
           (let ((res (org-agent::execute-llm-request "prompt" "sys" :provider :ollama)))
             (is (eq (getf res :status) :success))
             (is (equal "Ollama thought" (getf res :content)))))
      (setf (symbol-function 'dex:post) old-post))))

(test test-error-handling-missing-key
  "Ensure missing keys return a standardized error plist."
  ;; Clear environment
  (dolist (p '(:anthropic :openai :groq :openrouter :gemini-api))
    (setf (uiop:getenv (format nil "~a_API_KEY" (string-upcase (string p)))) ""))
  (let ((res (org-agent::execute-llm-request "test" "sys" :provider :openai)))
    (is (eq (getf res :status) :error))
    (is (search "API Key missing" (getf res :message)))))
