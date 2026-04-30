(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-memory-tests
  (:use :cl :fiveam :opencortex)
  (:export #:memory-suite))

(in-package :opencortex-memory-tests)

(def-suite memory-suite :description "Tests for the Merkle-Tree Memory")
(in-suite memory-suite)

(test merkle-hash-consistency
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil)))
    (clrhash opencortex::*memory*)
    (let ((id1 (ingest-ast ast1)))
      (let ((hash1 (org-object-hash (lookup-object id1))))
        (clrhash opencortex::*memory*)
        (let ((id2 (ingest-ast ast1)))
          (is (equal hash1 (org-object-hash (lookup-object id2)))))))))
