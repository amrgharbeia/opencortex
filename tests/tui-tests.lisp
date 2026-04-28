(defpackage :opencortex-tui-tests
  (:use :cl :fiveam :opencortex)
  (:export #:tui-suite))

(in-package :opencortex-tui-tests)

(def-suite tui-suite :description "Verification of the TUI parsing and styling logic")

(in-suite tui-suite)

(test test-tui-connection-drop
  "Tier 2 Chaos: Verify that handle-return degrades gracefully when the daemon connection is lost."
  (let ((opencortex.tui::*chat-history* nil)
        (opencortex.tui::*input-buffer* (make-array 5 :element-type 'char :initial-contents "hello" :fill-pointer 5 :adjustable t))
        ;; Create a closed stream to simulate connection drop
        (mock-stream (make-string-output-stream)))
    (close mock-stream)
    (opencortex.tui::handle-return mock-stream)
    ;; Check if the error was enqueued to history instead of crashing
    (is (member "ERROR: Connection to daemon lost." opencortex.tui::*chat-history* :test #'string=))))
