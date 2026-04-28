(defpackage :opencortex-literate-programming-tests
  (:use :cl :fiveam :opencortex)
  (:export #:literate-programming-suite))

(in-package :opencortex-literate-programming-tests)

(def-suite literate-programming-suite
  :description "Tests for Literate Programming enforcement")

(in-suite literate-programming-suite)

(test tangle-sync-detects-stale-lisp
  "check-tangle-sync returns violation when .lisp is newer than .org"
  (let* ((root (uiop:ensure-directory-pathname "/tmp/lp-test/"))
         (tmp-org (merge-pathnames "skills/test-skill.org" root))
         (tmp-lisp (merge-pathnames "library/gen/test-skill.lisp" root)))
    (uiop:ensure-all-directories-exist (list (directory-namestring tmp-org) (directory-namestring tmp-lisp)))
    (with-open-file (f tmp-org :direction :output) (write-line "* Test" f))
    (sleep 1)
    (with-open-file (f tmp-lisp :direction :output) (write-line "(defun test () t)" f))
    (let ((orig-targets opencortex::*tangle-targets*))
      (setf opencortex::*tangle-targets*
            (cons '("skills/test-skill.org" . "library/gen/test-skill.lisp") orig-targets))
      (unwind-protect
          (let ((result (opencortex::check-tangle-sync root)))
            (is (listp result))
            (is (eq :log (getf result :type)))
            (is (search "LITERATE PROGRAMMING VIOLATION" (getf (getf result :payload) :text))))
        (setf opencortex::*tangle-targets* orig-targets)))
    (uiop:delete-file-if-exists tmp-org)
    (uiop:delete-file-if-exists tmp-lisp)))

(test tangle-sync-passes-when-synced
  "check-tangle-sync returns nil when .org is newer than .lisp"
  (let* ((root (uiop:ensure-directory-pathname "/tmp/lp-test2/"))
         (tmp-org (merge-pathnames "skills/test-skill2.org" root))
         (tmp-lisp (merge-pathnames "library/gen/test-skill2.lisp" root)))
    (uiop:ensure-all-directories-exist (list (directory-namestring tmp-org) (directory-namestring tmp-lisp)))
    (with-open-file (f tmp-lisp :direction :output) (write-line "(defun test () t)" f))
    (sleep 1)
    (with-open-file (f tmp-org :direction :output) (write-line "* Test" f))
    (let ((orig-targets opencortex::*tangle-targets*))
      (setf opencortex::*tangle-targets*
            (cons '("skills/test-skill2.org" . "library/gen/test-skill2.lisp") orig-targets))
      (unwind-protect
          (let ((result (opencortex::check-tangle-sync root)))
            (is (null result)))
        (setf opencortex::*tangle-targets* orig-targets)))
    (uiop:delete-file-if-exists tmp-org)
    (uiop:delete-file-if-exists tmp-lisp)))

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
