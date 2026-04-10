(defpackage :org-agent-orchestrator-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-orchestrator-tests)

(def-suite orchestrator-suite :description "Tests for Event Orchestrator.")
(in-suite orchestrator-suite)

(test test-hook-execution
  (let ((test-val 0))
    (org-agent:orchestrator-register-hook :test-hook (lambda () (setf test-val 1)))
    (org-agent:orchestrator-trigger-hook :test-hook)
    (is (= 1 test-val))))

(test test-routing-reflex
  (let ((ctx '(:payload (:sensor :heartbeat))))
    (is (eq :REFLEX (org-agent:orchestrator-classify-complexity ctx)))))
