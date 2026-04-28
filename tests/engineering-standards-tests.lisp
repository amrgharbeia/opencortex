(defpackage :opencortex-engineering-standards-tests
  (:use :cl :fiveam :opencortex)
  (:export #:engineering-standards-suite))

(in-package :opencortex-engineering-standards-tests)

(def-suite engineering-standards-suite
  :description "Tests for Engineering Standards enforcement")

(in-suite engineering-standards-suite)

(test git-clean-check-clean
  "verify-git-clean-p returns T when git tree is clean."
  (let ((tmp-dir "/tmp/eng-std-test-clean/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    (uiop:run-program (list "git" "init" tmp-dir) :output nil)
    (is (eq t (opencortex::verify-git-clean-p (uiop:ensure-directory-pathname tmp-dir))))
    (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t)))
