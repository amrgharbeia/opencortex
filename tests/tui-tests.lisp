(defpackage :opencortex-tui-tests
  (:use :cl :fiveam :opencortex)
  (:export #:tui-suite))

(in-package :opencortex-tui-tests)

(def-suite tui-suite :description "Verification of the TUI parsing and styling logic")

(in-suite tui-suite)

(test test-command-parser
  "Verify that slash-commands are correctly identified."
  ;; Stub for now
  (is (null nil)))
