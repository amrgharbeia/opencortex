(defpackage :org-agent-lisp-validator-tests
  (:use :cl :fiveam :org-agent)
  (:export #:lisp-validator-suite))
(in-package :org-agent-lisp-validator-tests)

(def-suite lisp-validator-suite :description "Tests for the Lisp Validator.")
(in-suite lisp-validator-suite)

(test test-basic-math-safe
  (is (org-agent:lisp-validator-validate "(+ 1 2)")))

(test test-blocked-eval
  (is (not (org-agent:lisp-validator-validate "(eval '(+ 1 2))"))))

(test test-blocked-shell
  (is (not (org-agent:lisp-validator-validate "(uiop:run-program \"ls\")"))))

(test test-nested-unsafe
  (is (not (org-agent:lisp-validator-validate "(let ((x 1)) (delete-file \"test.txt\"))"))))

(test test-safe-kernel-api
  (is (org-agent:lisp-validator-validate "(org-agent::lookup-object \"node-1\")")))
