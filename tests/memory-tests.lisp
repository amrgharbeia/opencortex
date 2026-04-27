(defpackage :opencortex-memory-tests
  (:use :cl :fiveam :opencortex)
  (:export #:memory-suite))

(in-package :opencortex-memory-tests)

(def-suite memory-suite
  :description "Tests for the Merkle-Tree Memory.")

(in-suite memory-suite)

(test merkle-hash-consistency
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil))
         (ast2 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil)))
    (clrhash *memory*)
    (let ((id1 (ingest-ast ast1)))
      (let ((hash1 (org-object-hash (lookup-object id1))))
        (clrhash *memory*)
        (let ((id2 (ingest-ast ast2)))
          (let ((hash2 (org-object-hash (lookup-object id2))))
            (is (equal hash1 hash2))))))))

(test merkle-hash-cascading
  (let* ((ast-leaf '(:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))
         (ast-root-full '(:type :HEADLINE :properties (:ID "root" :TITLE "Root") 
                           :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))))
         (id-root (progn (clrhash *memory*) (ingest-ast ast-root-full)))
         (initial-root-hash (org-object-hash (lookup-object id-root))))
      
      ;; Now ingest a modified version (title change)
      (let* ((ast-root-modified '(:type :HEADLINE :properties (:ID "root" :TITLE "Root") 
                                 :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf Modified") :contents nil))))
             (id-root-mod (progn (clrhash *memory*) (ingest-ast ast-root-modified)))
             (modified-root-hash (org-object-hash (lookup-object id-root-mod))))
        (is (not (equal initial-root-hash modified-root-hash))))))

(test history-store-immutability
  "Verify that *history-store* retains old versions even after *memory* updates."
  (clrhash *memory*)
  (clrhash *history-store*)
  (let* ((ast-v1 '(:type :HEADLINE :properties (:ID "test-node" :TITLE "Version 1") :contents nil))
         (id-v1 (ingest-ast ast-v1))
         (obj-v1 (lookup-object id-v1))
         (hash-v1 (org-object-hash obj-v1)))
    
    (let* ((ast-v2 '(:type :HEADLINE :properties (:ID "test-node" :TITLE "Version 2") :contents nil))
           (id-v2 (ingest-ast ast-v2))
           (obj-v2 (lookup-object id-v2))
           (hash-v2 (org-object-hash obj-v2)))
      
      ;; The active pointer should be v2
      (is (equal (org-object-hash (lookup-object "test-node")) hash-v2))
      
      ;; Both v1 and v2 should exist in the immutable history store
      (is (not (null (gethash hash-v1 *history-store*))))
      (is (not (null (gethash hash-v2 *history-store*))))
      
      ;; Modifying v2 should not affect v1 in the history store
      (is (equal (org-object-content (gethash hash-v1 *history-store*)) "Version 1
"))
      (is (equal (org-object-content (gethash hash-v2 *history-store*)) "Version 2
")))))

(test cow-snapshot-and-rollback
  "Verify that lightweight snapshots can accurately restore previous pointer states."
  (clrhash *memory*)
  (clrhash *history-store*)
  (setf *object-store-snapshots* nil)
  
  (let* ((ast-v1 '(:type :HEADLINE :properties (:ID "cow-node" :TITLE "State A") :contents nil))
         (id-v1 (ingest-ast ast-v1))
         (hash-v1 (org-object-hash (lookup-object id-v1))))
     
    ;; Take a snapshot at State A
    (snapshot-memory)
    
    (let* ((ast-v2 '(:type :HEADLINE :properties (:ID "cow-node" :TITLE "State B") :contents nil))
           (id-v2 (ingest-ast ast-v2))
           (hash-v2 (org-object-hash (lookup-object id-v2))))
      
      ;; Verify we are currently in State B
      (is (equal (org-object-hash (lookup-object "cow-node")) hash-v2))
      
      ;; Rollback to State A (index 0 because we only took 1 snapshot)
      (rollback-memory 0)
      
      ;; Verify we are back in State A
      (is (equal (org-object-hash (lookup-object "cow-node")) hash-v1))
      
;; Verify State B is still safely in the history store (no data loss)
      (is (not (null (gethash hash-v2 *history-store*)))))))

(test merkle-hash-consistency
  "Verify that identical ASTs produce identical Merkle hashes."
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil)))
    (clrhash *memory*)
    (let ((id1 (ingest-ast ast1)))
      (let ((hash1 (org-object-hash (lookup-object id1))))
        (clrhash *memory*)
        (let ((id2 (ingest-ast ast1)))
          (let ((hash2 (org-object-hash (lookup-object id2))))
            (is (equal hash1 hash2))))))))

(test merkle-hash-cascading
  "Verify that child changes propagate to parent hashes."
  (let* ((ast-root '(:type :HEADLINE :properties (:ID "root" :TITLE "Root")
                      :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))))
         (id-root (progn (clrhash *memory*) (ingest-ast ast-root)))
         (root-hash (org-object-hash (lookup-object id-root))))
    ;; Now ingest a modified child - parent hash should change
    (let* ((ast-mod '(:type :HEADLINE :properties (:ID "root" :TITLE "Root")
                    :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Changed") :contents nil))))
           (id-mod (progn (clrhash *memory*) (ingest-ast ast-mod)))
            (mod-hash (org-object-hash (lookup-object id-mod))))
      (is (not (equal root-hash mod-hash))))))
