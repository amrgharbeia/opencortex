(defpackage :org-agent-memory-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-memory-tests)

(def-suite memory-suite :description "Tests for Homoiconic Memory.")
(in-suite memory-suite)

(test test-id-injection
  (let* ((node (list :type :HEADLINE :properties nil))
         (normalized (org-agent::memory-ensure-id node)))
    (is (not (null (getf (getf normalized :properties) :ID))))))
