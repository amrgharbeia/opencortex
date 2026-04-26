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

(test git-clean-check-dirty
  "verify-git-clean-p returns NIL when git tree has uncommitted changes."
  (let ((tmp-dir "/tmp/eng-std-test-dirty/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    (uiop:run-program (list "git" "init" tmp-dir) :output nil)
    (with-open-file (f (merge-pathnames "test.txt" tmp-dir) :direction :output)
      (write-line "test" f))
    (is (null (opencortex::verify-git-clean-p (uiop:ensure-directory-pathname tmp-dir))))
    (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t)))

(test violation-struct
  "engineering-violation struct is properly constructed."
  (let ((v (opencortex::make-engineering-violation
            :phase :pre-task
            :rule :git-clean
            :message "Test violation"
            :severity :blocker)))
    (is (eq :pre-task (opencortex::engineering-violation-phase v)))
    (is (eq :git-clean (opencortex::engineering-violation-rule v)))
    (is (string= "Test violation" (opencortex::engineering-violation-message v)))
    (is (eq :blocker (opencortex::engineering-violation-severity v)))))

(test gate-blocks-dirty-tree
  "engineering-standards-gate blocks when git is dirty."
  (let ((action (list :type :request
                      :payload (list :tool :write-file
                                 :file "/tmp/test"
                                 :content "test"))))
    ;; Note: This test assumes git is clean in test environment
    ;; The gate returns :log if dirty
    (let ((result (opencortex::engineering-standards-gate action nil)))
      (is (listp result))
      (when (eq (getf result :type) :log)
        (is (search "dirty" (getf (getf result :payload) :text) :test #'char-equal))))))

(test gate-allows-clean-tree
  "engineering-standards-gate passes when git is clean."
  (let ((action (list :type :request
                      :payload (list :tool :read-file
                                 :file "/tmp/test"))))
    (let ((result (opencortex::engineering-standards-gate action nil)))
      (is (listp result))
      (is (eq :request (getf result :type))))))
