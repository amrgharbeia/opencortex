(defpackage :org-agent-lisp-repair-tests
  (:use :cl :fiveam :org-agent)
  (:export #:lisp-repair-suite))
(in-package :org-agent-lisp-repair-tests)

(def-suite lisp-repair-suite :description "Tests for Asynchronous Lisp Repair Syntax Gate.")
(in-suite lisp-repair-suite)

(test test-deterministic-repair-balance
  "Verify that deterministic-repair balances parentheses."
  (let ((broken "(:type :REQUEST :target :emacs"))
    ;; deterministic-repair will be defined in lisp-repair.lisp (user-space)
    ;; but for testing we expect it to be available in the org-agent package.
    (is (equal "(:type :REQUEST :target :emacs)" 
               (org-agent::deterministic-repair broken)))))

(test test-async-repair-flow
  "Verify that the pipeline correctly emits and reacts to syntax-error events."
  (clrhash org-agent::*memory*)
  (let* ((broken-code "(:type :REQUEST :target :tool")
         (error-msg "End of file")
         ;; 1. The Stimulus that caused the error
         (stimulus `(:type :EVENT :payload (:sensor :syntax-error :code ,broken-code :error ,error-msg)))
         ;; 2. Simulate the decide-gate call for skill-lisp-repair
         (result (org-agent:decide-gate (list :type :EVENT :candidate stimulus :payload '(:sensor :syntax-error)))))
    
    (let ((approved (getf result :approved-action)))
      ;; The repair skill should have intercepted the EVENT and returned a repaired REQUEST
      (is (eq :REQUEST (getf approved :type)))
      (is (eq :tool (getf approved :target))))))
