(defpackage :opencortex-tui-tests
  (:use :cl :opencortex)
  (:export #:tui-suite))

(in-package :opencortex-tui-tests)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(fiveam:def-suite tui-suite :description "Verification of the TUI parsing and styling logic")
(fiveam:in-suite tui-suite)

(fiveam:test test-tui-connection-drop
  "Tier 2 Chaos: Verify that handle-return degrades gracefully when the daemon connection is lost."
  (let ((opencortex.tui::*incoming-msgs* nil)
         (opencortex.tui::*input-buffer* (make-array 5 :element-type 'character :initial-contents "hello" :fill-pointer 5 :adjustable t))
        ;; Create a closed stream to simulate connection drop
        (mock-stream (make-string-output-stream)))
    (close mock-stream)
    (opencortex.tui::handle-return mock-stream)
    ;; Check if the error was enqueued to history instead of crashing
    (fiveam:is (member "ERROR: Connection to daemon lost." opencortex.tui::*incoming-msgs* :test #'string=))))
