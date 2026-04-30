(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-pipeline-act-tests
  (:use :cl :fiveam :opencortex)
  (:export #:pipeline-act-suite))

(in-package :opencortex-pipeline-act-tests)

(def-suite pipeline-act-suite :description "Test suite for Act pipeline")
(in-suite pipeline-act-suite)

(test test-act-gate-basic
  (clrhash opencortex::*skills-registry*)
  (let* ((signal (list :type :EVENT :status nil :depth 0 :approved-action '(:target :cli :payload (:text "Hello"))))
         (result (act-gate signal)))
    (is (eq :acted (getf signal :status)))
    (is (null result))))
