(defpackage :opencortex-diagnostics-tests
  (:use :cl :fiveam :opencortex)
  (:export #:diagnostics-suite))

(in-package :opencortex-diagnostics-tests)

(def-suite diagnostics-suite :description "Verification of the Diagnostics skill")

(in-suite diagnostics-suite)

(test test-dependency-check-fail
  "Verify that missing binaries are correctly identified as failures."
  (let ((opencortex::*doctor-required-binaries* '("non-existent-binary-123")))
    (is (null (opencortex:doctor-check-dependencies)))))
