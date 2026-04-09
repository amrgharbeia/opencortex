(defpackage :org-agent-safety-tests
  (:use :cl :fiveam :org-agent)
  (:export #:safety-suite))
(in-package :org-agent-safety-tests)

(def-suite safety-suite :description "Tests for the Global Safety Harness.")
(in-suite safety-suite)

(test test-basic-math-safe
  (is (org-agent:safety-harness-validate "(+ 1 2)")))

(test test-blocked-eval
  (is (not (org-agent:safety-harness-validate "(eval '(+ 1 2))"))))

(test test-blocked-shell
  (is (not (org-agent:safety-harness-validate "(uiop:run-program \"ls\")"))))

(test test-nested-unsafe
  (is (not (org-agent:safety-harness-validate "(let ((x 1)) (delete-file \"test.txt\"))"))))

(test test-safe-kernel-api
  (is (org-agent:safety-harness-validate "(org-agent::lookup-object \"node-1\")")))
