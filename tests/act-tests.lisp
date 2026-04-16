(defpackage :opencortex-act-tests
  (:use :cl :fiveam :opencortex))
(in-package :opencortex-act-tests)

(def-suite act-suite
  :description "Verification of the Act Gate and Symbolic Guard.")
(in-suite act-suite)

(test test-act-gate-symbolic-guard-bypass
  "Verify that opencortex:act-gate proceeds normally when no skill intercepts."
  (clrhash opencortex::*skills-registry*)
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :cli :payload (:text "Hello"))))
         (result (opencortex:act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (null result))))

(test test-act-gate-symbolic-guard-interception
  "Verify that opencortex:act-gate intercepts actions when a skill returns a LOG/EVENT."
  (clrhash opencortex::*skills-registry*)
  ;; Register a mock skill that acts like a symbolic guard
  (opencortex::defskill :mock-bouncer
    :priority 200
    :trigger (lambda (ctx) t)
    :deterministic (lambda (action ctx)
                     (declare (ignore action ctx))
                     '(:type :LOG :payload (:text "BLOCKED BY SYMBOLIC GUARD"))))
  
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :shell :payload (:cmd "ls"))))
         (result (opencortex:act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (not (null result)))
    (is (eq :LOG (getf result :type)))
    (is (search "BLOCKED BY SYMBOLIC GUARD" (getf (getf result :payload) :text)))
    ;; The approved action in signal should be NIL'd out
    (is (null (getf signal :approved-action)))))

(test test-act-gate-symbolic-guard-pass-through
  "Verify that opencortex:act-gate allows actions when skills permit them."
  (clrhash opencortex::*skills-registry*)
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :cli :payload (:text "Allowed"))))
         (result (opencortex:act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (equal '(:target :cli :payload (:text "Allowed")) (getf signal :approved-action)))))
