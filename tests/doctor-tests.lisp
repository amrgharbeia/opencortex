(defpackage :opencortex-doctor-tests
  (:use :cl :fiveam :opencortex)
  (:export #:doctor-suite))

(in-package :opencortex-doctor-tests)

(def-suite doctor-suite :description "Verification of the System Doctor diagnostic logic")

(in-suite doctor-suite)

(test test-dependency-check-fail
  "Verify that missing binaries are correctly identified as failures."
  (let ((opencortex::*doctor-required-binaries* '("non-existent-binary-123")))
    (is (null (opencortex:doctor-check-dependencies)))))

(test test-env-validation-fail
  "Verify that an invalid MEMEX_DIR triggers a critical failure."
  (let ((old-m (uiop:getenv "MEMEX_DIR"))
        (old-s (uiop:getenv "SKILLS_DIR")))
    (unwind-protect
         (progn
           (setf (uiop:getenv "MEMEX_DIR") "/non/existent/path/999")
           (is (null (opencortex:doctor-check-env))))
      (setf (uiop:getenv "MEMEX_DIR") (or old-m ""))
      (setf (uiop:getenv "SKILLS_DIR") (or old-s "")))))
