(defpackage :opencortex-pipeline-perceive-tests
  (:use :cl :fiveam :opencortex)
  (:export #:pipeline-perceive-suite))

(in-package :opencortex-pipeline-perceive-tests)

(def-suite pipeline-perceive-suite
  :description "Test suite for Perceive pipeline")

(in-suite pipeline-perceive-suite)

(test test-perceive-gate
  "Perceive gate should update the object store and normalize signal."
  (clrhash opencortex::*memory*)
  (let* ((signal (list :type :EVENT :payload (list :sensor :buffer-update :ast (list :type :HEADLINE :properties (list :ID "test-node" :TITLE "Test") :contents nil))))
         (result (perceive-gate signal)))
    (is (eq :perceived (getf result :status)))
    (is (not (null (gethash "test-node" opencortex::*memory*))))))

(test test-depth-limiting
  "Verify that the pipeline terminates runaway feedback loops."
  (let ((runaway-signal (list :type :EVENT :depth 11 :payload (list :sensor :heartbeat))))
    (is (null (process-signal runaway-signal)))))
