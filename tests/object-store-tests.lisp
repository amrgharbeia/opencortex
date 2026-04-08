(defpackage :org-agent-object-store-tests
  (:use :cl :fiveam :org-agent)
  (:export #:object-store-suite))

(in-package :org-agent-object-store-tests)

(def-suite object-store-suite
  :description "Tests for the Merkle-Tree Object Store.")

(in-suite object-store-suite)

(test merkle-hash-consistency
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil))
         (ast2 '(:type :HEADLINE :properties (:ID "test-1" :TITLE "Node 1") :contents nil)))
    (clrhash *object-store*)
    (let ((id1 (ingest-ast ast1)))
      (let ((hash1 (org-object-hash (lookup-object id1))))
        (clrhash *object-store*)
        (let ((id2 (ingest-ast ast2)))
          (let ((hash2 (org-object-hash (lookup-object id2))))
            (is (equal hash1 hash2))))))))

(test merkle-hash-cascading
  (let* ((ast-leaf '(:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))
         (ast-root-full '(:type :HEADLINE :properties (:ID "root" :TITLE "Root") 
                           :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))))
         (id-root (progn (clrhash *object-store*) (ingest-ast ast-root-full)))
         (initial-root-hash (org-object-hash (lookup-object id-root))))
      
      ;; Now ingest a modified version (title change)
      (let* ((ast-root-modified '(:type :HEADLINE :properties (:ID "root" :TITLE "Root") 
                                 :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf Modified") :contents nil))))
             (id-root-mod (progn (clrhash *object-store*) (ingest-ast ast-root-modified)))
             (modified-root-hash (org-object-hash (lookup-object id-root-mod))))
        (is (not (equal initial-root-hash modified-root-hash))))))

(test merkle-hash-property-change
  "Verify that changing only a property drawer value changes the hash."
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "prop-test" :STATUS "TODO") :contents nil))
         (ast2 '(:type :HEADLINE :properties (:ID "prop-test" :STATUS "DONE") :contents nil)))
    (clrhash *object-store*)
    (let* ((id1 (ingest-ast ast1))
           (hash1 (org-object-hash (lookup-object id1))))
      (clrhash *object-store*)
      (let* ((id2 (ingest-ast ast2))
             (hash2 (org-object-hash (lookup-object id2))))
        (is (not (equal hash1 hash2)))))))

(test merkle-hash-deep-cascade
  "Verify that a change in a 3rd-level leaf cascades to the root."
  (let* ((ast-deep '(:type :HEADLINE :properties (:ID "root" :TITLE "Root")
                     :contents ((:type :HEADLINE :properties (:ID "mid" :TITLE "Mid")
                                 :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf") :contents nil))))))
         (id-root (progn (clrhash *object-store*) (ingest-ast ast-deep)))
         (hash-initial (org-object-hash (lookup-object id-root))))
    
    (let* ((ast-deep-mod '(:type :HEADLINE :properties (:ID "root" :TITLE "Root")
                           :contents ((:type :HEADLINE :properties (:ID "mid" :TITLE "Mid")
                                       :contents ((:type :HEADLINE :properties (:ID "leaf" :TITLE "Leaf Changed") :contents nil))))))
           (id-root-mod (progn (clrhash *object-store*) (ingest-ast ast-deep-mod)))
           (hash-mod (org-object-hash (lookup-object id-root-mod))))
      (is (not (equal hash-initial hash-mod))))))
