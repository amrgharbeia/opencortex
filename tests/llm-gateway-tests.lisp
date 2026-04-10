(defpackage :org-agent-llm-gateway-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-llm-gateway-tests)

(def-suite llm-gateway-suite :description "Tests for the Unified LLM Gateway.")
(in-suite llm-gateway-suite)

(test test-credential-retrieval
  "Ensure credentials are retrieved from the correct environment variables."
  (uiop:setenv "ANTHROPIC_API_KEY" "sk-test-key")
  (is (equal "sk-test-key" (org-agent::get-llm-credentials :anthropic)))
  (uiop:setenv "ANTHROPIC_API_KEY" ""))

(test test-error-handling-missing-key
  "Ensure missing keys return a standardized error plist."
  (let ((res (org-agent:execute-llm-request "test" "sys" :provider :openai)))
    (is (eq (getf res :status) :error))
    (is (search "API Key missing" (getf res :message)))))
