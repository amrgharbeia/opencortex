(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-communication-tests
  (:use :cl :fiveam :opencortex)
  (:export #:communication-protocol-suite))
(in-package :opencortex-communication-tests)

(def-suite communication-protocol-suite :description "Communication Protocol Suite")
(in-suite communication-protocol-suite)

(test test-framing
  (let* ((msg '(:type :EVENT :payload (:action :handshake)))
         (framed (frame-message msg)))
    (is (string= "00002C" (string-upcase (subseq framed 0 6))))))
