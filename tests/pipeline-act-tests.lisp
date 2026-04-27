(defpackage :opencortex-pipeline-act-tests
  (:use :cl :fiveam :opencortex)
  (:export #:pipeline-act-suite))

(in-package :opencortex-pipeline-act-tests)

(def-suite pipeline-act-suite
  :description "Test suite for Act pipeline")

(in-suite pipeline-act-suite)

(test test-act-gate-symbolic-guard-bypass
  "Verify that act-gate proceeds normally when no skill intercepts."
  (clrhash opencortex::*skills-registry*)
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :cli :payload (:text "Hello"))))
         (result (opencortex:act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (null result))))

(test test-act-gate-symbolic-guard-interception
  "Verify that act-gate intercepts actions when a skill returns a LOG/EVENT."
  (clrhash opencortex::*skills-registry*)
  (opencortex::defskill :mock-bouncer
    :priority 200
    :trigger (lambda (ctx) t)
    :deterministic (lambda (action ctx)
                     (list :type :LOG :payload '(:text "BLOCKED BY SYMBOLIC GUARD"))))
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :shell :payload (:cmd "ls"))))
         (result (opencortex:act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (not (null result)))
    (is (eq :LOG (getf result :type)))
    (is (search "BLOCKED BY SYMBOLIC GUARD" (getf (getf result :payload) :text)))))
