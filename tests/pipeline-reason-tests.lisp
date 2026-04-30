(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-pipeline-reason-tests
  (:use :cl :fiveam :opencortex)
  (:export #:pipeline-reason-suite))

(in-package :opencortex-pipeline-reason-tests)

(def-suite pipeline-reason-suite :description "Test suite for Reason pipeline")
(in-suite pipeline-reason-suite)

(test test-decide-gate-safety
  (clrhash opencortex::*skills-registry*)
  (opencortex::defskill :mock-safety
    :priority 50
    :trigger (lambda (ctx) (declare (ignore ctx)) t)
    :deterministic (lambda (action ctx)
                    (declare (ignore ctx))
                    (if (search "rm -rf" (format nil "~s" action))
                        (list :type :LOG :payload (list :text "Rejected"))
                        action)))
  (let* ((candidate '(:type :REQUEST :payload (:action :shell :cmd "rm -rf /")))
         (signal '(:type :EVENT :payload (:sensor :user-input)))
         (result (deterministic-verify candidate signal)))
    (is (eq :LOG (getf result :type)))))
