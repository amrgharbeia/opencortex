(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-llm-gateway-tests
  (:use :cl :opencortex)
  (:export #:llm-gateway-suite))

(in-package :opencortex-llm-gateway-tests)

(fiveam:def-suite llm-gateway-suite :description "Tests for the LLM Gateway skill")
(fiveam:in-suite llm-gateway-suite)

(fiveam:test test-llm-gateway-timeout
  "Tier 2 Chaos: Verify that LLM Gateway handles connection failures gracefully."
  (let ((old-host (uiop:getenv "OLLAMA_HOST")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "OLLAMA_HOST") "localhost:1")
           (let ((fn (or (find-symbol "EXECUTE-LLM-REQUEST" :opencortex.skills.org-skill-llm-gateway)
                         (find-symbol "EXECUTE-LLM-REQUEST" :opencortex))))
             (if fn
                 (let ((result (funcall fn :prompt "hello" :provider :ollama)))
                   (fiveam:is (eq (getf result :status) :error))
                   (fiveam:is (uiop:string-prefix-p "Ollama Failure" (getf result :message))))
                 (fiveam:fail "Could not find EXECUTE-LLM-REQUEST symbol"))))
      (if old-host
          (setf (uiop:getenv "OLLAMA_HOST") old-host)
          (sb-posix:unsetenv "OLLAMA_HOST")))))
