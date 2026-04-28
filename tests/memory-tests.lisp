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

(test test-merkle-corruption-rollback
  "Tier 2 Chaos: Verify that Merkle hash corruption triggers a Micro-Rollback."
  (clrhash *memory*)
  (setf *object-store-snapshots* nil)
  (let* ((ast '(:type :HEADLINE :properties (:ID "node-1" :TITLE "Original") :contents nil))
         (id (ingest-ast ast)))
    (snapshot-memory)
    ;; Manually corrupt the hash in the live memory
    (let ((obj (lookup-object id)))
      (setf (org-object-hash obj) "CORRUPTED-HASH"))
    
    ;; Simulate a system integrity check that should fail and rollback
    ;; We'll use a manual check here since automatic validation is in the Loop
    (let ((obj (lookup-object id)))
      (let ((current-hash (org-object-hash obj))
            (computed-hash (compute-merkle-hash (org-object-id obj) 
                                               (org-object-type obj)
                                               (org-object-attributes obj)
                                               (org-object-content obj)
                                               nil)))
        (unless (string= current-hash computed-hash)
          (rollback-memory 0))))
    
    ;; Verify that the memory was rolled back to the clean snapshot
    (is (string/= "CORRUPTED-HASH" (org-object-hash (lookup-object id))))))
