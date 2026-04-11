(defpackage :org-agent-task-orchestrator-tests
  (:use :cl :fiveam :org-agent)
  (:export #:task-orchestrator-suite))
(in-package :org-agent-task-orchestrator-tests)

(def-suite task-orchestrator-suite :description "Tests for Consolidation VI: Task Orchestrator.")
(in-suite task-orchestrator-suite)

(test test-consensus-gate-divergence
  "Verify that consensus-gate handles diverging proposals by selecting the safest one."
  (let* ((proposals '((:type :REQUEST :target :tool :action :call :tool "shell" :args (:cmd "rm -rf /"))
                      (:type :REQUEST :target :tool :action :call :tool "grep-search" :args (:pattern "sovereignty"))
                      (:type :REQUEST :target :tool :action :call :tool "grep-search" :args (:pattern "sovereignty"))))
         (signal `(:type :EVENT :status :thought :proposals ,proposals))
         (result (org-agent:consensus-gate signal)))
    ;; The judge should reject the 'rm -rf' and select the matching grep-search
    (is (equal (getf (getf result :candidate) :tool) "grep-search"))
    (is (eq :consensus (getf result :status)))))

(test test-task-integrity-parent-child
  "Verify that task-integrity-check rejects closing a parent with active children."
  ;; Mocking some objects in the store
  (clrhash org-agent::*object-store*)
  (setf (gethash "parent-1" org-agent::*object-store*)
        (org-agent::make-org-object :id "parent-1" :attributes '(:TITLE "Parent Task" :TODO "TODO")))
  (setf (gethash "child-1" org-agent::*object-store*)
        (org-agent::make-org-object :id "child-1" :attributes '(:TITLE "Child Task" :TODO "TODO" :PARENT "parent-1")))
  
  (let* ((action '(:type :REQUEST :target :emacs :action :update-node :id "parent-1" :attributes (:TODO "DONE")))
         (signal `(:type :EVENT :payload (:sensor :test) :candidate ,action))
         (result (org-agent:decide-gate signal)))
    ;; Should be blocked by Task Integrity
    (let ((approved (getf result :approved-action)))
      (is (equal (getf (getf approved :payload) :text) "Blocked by Task Integrity: Active children exist.")))))
