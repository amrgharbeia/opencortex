(defpackage :opencortex-llm-gateway-tests
  (:use :cl :fiveam :opencortex)
  (:export #:llm-gateway-suite))

(in-package :opencortex-llm-gateway-tests)

(def-suite llm-gateway-suite :description "Tests for the LLM Gateway skill")
(in-suite llm-gateway-suite)

(test test-llm-gateway-timeout
  "Tier 2 Chaos: Verify that LLM Gateway handles connection failures gracefully."
  ;; Point to a non-existent port to force a connection error
  (let ((uiop:*environment* (copy-list uiop:*environment*)))
    (setf (uiop:getenv "OLLAMA_HOST") "localhost:1")
    (let ((result (opencortex::execute-llm-request :prompt "hello" :provider :ollama)))
      (is (eq (getf result :status) :error))
      (is (uiop:string-prefix-p "Ollama Failure" (getf result :message))))))
