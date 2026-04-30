(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :fiveam :silent t))

(defpackage :opencortex-boot-tests
  (:use :cl :fiveam :opencortex)
  (:export #:boot-suite))

(in-package :opencortex-boot-tests)

(def-suite boot-suite :description "Verification of the Skill Engine loader")
(in-suite boot-suite)

(test test-topological-sort-basic
  (let ((tmp-dir "/tmp/opencortex-boot-test/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    (with-open-file (out (merge-pathnames "org-skill-a.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+DEPENDS_ON: skill-b-id~%"))
    (with-open-file (out (merge-pathnames "org-skill-b.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: skill-b-id~%:END:~%"))
    (unwind-protect
         (let ((sorted (opencortex::topological-sort-skills tmp-dir)))
           (let ((pos-a (position "org-skill-a" sorted :key #'pathname-name :test #'string-equal))
                 (pos-b (position "org-skill-b" sorted :key #'pathname-name :test #'string-equal)))
             (is (< pos-b pos-a))))
       (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t))))
