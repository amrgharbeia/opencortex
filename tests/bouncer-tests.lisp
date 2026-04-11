(defpackage :org-agent-bouncer-tests
  (:use :cl :fiveam :org-agent)
  (:export #:bouncer-suite))
(in-package :org-agent-bouncer-tests)

(def-suite bouncer-suite :description "Tests for System 2 Bouncer & Authorization Gate.")
(in-suite bouncer-suite)

(test test-bouncer-interception
  "Verify that a high-risk action is intercepted by the bouncer."
  (let* ((action '(:type :REQUEST :target :tool :action :call :tool "shell" :args (:cmd "rm -rf /")))
         (context '(:payload (:sensor :test)))
         (result (org-agent:decide-gate (list :type :EVENT :candidate action :payload '(:sensor :test)))))
    (let ((approved (getf result :approved-action)))
      ;; Result should be an EVENT requiring approval, not the original REQUEST
      (is (eq :EVENT (getf approved :type)))
      (is (eq :approval-required (getf (getf approved :payload) :sensor)))
      (is (equal action (getf (getf approved :payload) :action))))))

(test test-bouncer-bypass
  "Verify that an approved action bypasses the bouncer."
  (let* ((action '(:type :REQUEST :target :tool :action :call :tool "shell" :args (:cmd "ls") :approved t))
         (context '(:payload (:sensor :test)))
         (result (org-agent:decide-gate (list :type :EVENT :candidate action :payload '(:sensor :test)))))
    (let ((approved (getf result :approved-action)))
      ;; Result should be the original action because it has :approved t
      (is (eq :REQUEST (getf approved :type)))
      (is (equal action approved)))))

(test test-bouncer-approval-reaction
  "Verify that the bouncer skill re-injects an action when a plan node is APPROVED."
  (clrhash org-agent::*object-store*)
  (let* ((action '(:type :REQUEST :target :tool :action :call :tool "ls"))
         (node-id "plan-1"))
    ;; 1. Setup an APPROVED flight plan node
    (setf (gethash node-id org-agent::*object-store*)
          (org-agent::make-org-object 
           :id node-id 
           :attributes `(:TITLE "Flight Plan" :TODO "APPROVED" :TAGS ("FLIGHT_PLAN") :ACTION ,(format nil "~s" action))))
    
    ;; 2. Manually trigger the bouncer's approval checker
    (let ((result (org-agent::bouncer-process-approvals)))
      (is (eq t result))
      ;; The node should now be DONE
      (let ((obj (gethash node-id org-agent::*object-store*)))
        (is (equal "DONE" (getf (org-agent:org-object-attributes obj) :TODO)))))))
