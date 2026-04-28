(defpackage :opencortex-memory-tests
  (:use :cl :fiveam :opencortex)
  (:export #:memory-suite))

(in-package :opencortex-memory-tests)

(def-suite memory-suite
  :description "Tests for the Merkle-Tree Memory")

(in-suite memory-suite)

(test merkle-hash-consistency
  "Verify identical ASTs produce identical Merkle hashes."
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil)))
    (clrhash *memory*)
    (let ((id1 (ingest-ast ast1)))
      (let ((hash1 (org-object-hash (lookup-object id1))))
        (clrhash *memory*)
        (let ((id2 (ingest-ast ast1)))
          (let ((hash2 (org-object-hash (lookup-object id2))))
            (is (equal hash1 hash2))))))))

(test history-store-immutability
  "Verify that *history-store* retains old versions."
  (clrhash *memory*)
  (clrhash *history-store*)
  (let* ((ast-v1 '(:type :HEADLINE :properties (:ID "test-node" :TITLE "Version 1") :contents nil))
         (id-v1 (ingest-ast ast-v1))
         (obj-v1 (lookup-object id-v1))
         (hash-v1 (org-object-hash obj-v1)))
    (let* ((ast-v2 '(:type :HEADLINE :properties (:ID "test-node" :TITLE "Version 2") :contents nil))
           (id-v2 (ingest-ast ast-v2))
           (hash-v2 (org-object-hash (lookup-object id-v2))))
      (is (equal (org-object-hash (lookup-object "test-node")) hash-v2))
      (is (not (null (gethash hash-v1 *history-store*))))
      (is (not (null (gethash hash-v2 *history-store*)))))))

(test cow-snapshot-and-rollback
  "Verify that lightweight snapshots restore previous pointer states."
  (clrhash *memory*)
  (setf *object-store-snapshots* nil)
  (let* ((ast-v1 '(:type :HEADLINE :properties (:ID "cow-node" :TITLE "State A") :contents nil))
         (id-v1 (ingest-ast ast-v1))
         (hash-v1 (org-object-hash (lookup-object id-v1))))
    (snapshot-memory)
    (let* ((ast-v2 '(:type :HEADLINE :properties (:ID "cow-node" :TITLE "State B") :contents nil))
           (id-v2 (ingest-ast ast-v2))
           (hash-v2 (org-object-hash (lookup-object id-v2))))
      (is (equal (org-object-hash (lookup-object "cow-node")) hash-v2))
      (rollback-memory 0)
      (is (equal (org-object-hash (lookup-object "cow-node")) hash-v1)))))
