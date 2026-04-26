(defpackage :opencortex-literate-programming-tests
  (:use :cl :fiveam :opencortex)
  (:export #:literate-programming-suite))

(in-package :opencortex-literate-programming-tests)

(def-suite literate-programming-suite
  :description "Tests for Literate Programming enforcement")

(in-suite literate-programming-suite)

(test tangle-sync-detects-stale-lisp
  "check-tangle-sync returns violation when .lisp is newer than .org"
  (let ((tmp-org "/tmp/test-skill.org")
        (tmp-lisp "/tmp/test-skill.lisp"))
    (with-open-file (f tmp-org :direction :output) (write-line "* Test" f))
    (sleep 1)
    (with-open-file (f tmp-lisp :direction :output) (write-line "(defun test () t)" f))
    (let* ((root (uiop:ensure-directory-pathname "/tmp/"))
           (result (opencortex::check-tangle-sync root)))
      (is (listp result))
      (is (eq :log (getf result :type)))
      (is (search "LITERATE PROGRAMMING VIOLATION" (getf (getf result :payload) :text)))
      (uiop:delete-file-if-exists tmp-org)
      (uiop:delete-file-if-exists tmp-lisp))))

(test tangle-sync-passes-when-synced
  "check-tangle-sync returns nil when .org is newer than .lisp"
  (let ((tmp-org "/tmp/test-skill2.org")
        (tmp-lisp "/tmp/test-skill2.lisp"))
    (with-open-file (f tmp-lisp :direction :output) (write-line "(defun test () t)" f))
    (sleep 1)
    (with-open-file (f tmp-org :direction :output) (write-line "* Test" f))
    (let* ((root (uiop:ensure-directory-pathname "/tmp/"))
           (result (opencortex::check-tangle-sync root)))
      (is (null result)))
    (uiop:delete-file-if-exists tmp-org)
    (uiop:delete-file-if-exists tmp-lisp)))

(test block-balance-valid
  "literate-check-block-balance returns T for balanced code"
  (is (eq t (opencortex::literate-check-block-balance "(defun test () t)"))))

(test block-balance-invalid
  "literate-check-block-balance returns NIL for unbalanced code"
  (multiple-value-bind (ok reason) (opencortex::literate-check-block-balance "(defun test ()")
    (is (null ok))
    (is (stringp reason))))
