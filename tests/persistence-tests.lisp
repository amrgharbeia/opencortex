(defpackage :org-agent-persistence-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-persistence-tests)

(def-suite persistence-suite :description "Tests for State Persistence Layer.")
(in-suite persistence-suite)

(test test-local-roundtrip
  "Ensure RAM -> Disk -> RAM preserves data integrity."
  (let ((test-id "persist-test-1"))
    (setf (gethash test-id *memory*) (make-org-object :id test-id :content "Integrity Check"))
    (org-agent:persistence-dump-local)
    (clrhash *memory*)
    (org-agent:persistence-load-local)
    (is (equal "Integrity Check" (org-object-content (gethash test-id *memory*))))))
