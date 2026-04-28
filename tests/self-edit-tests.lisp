(defpackage :opencortex-self-edit-tests
  (:use :cl :fiveam :opencortex)
  (:export #:self-edit-suite))

(in-package :opencortex-self-edit-tests)

(def-suite self-edit-suite
  :description "Tests for Self-Edit skill.")

(in-suite self-edit-suite)

(test balance-parens-balanced
  (let ((result (opencortex::self-edit-balance-parens "(+ 1 2)")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-missing-open
  (let ((result (opencortex::self-edit-balance-parens "+ 1 2)")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-missing-close
  (let ((result (opencortex::self-edit-balance-parens "(+ 1 2")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-deep
  (let ((result (opencortex::self-edit-balance-parens "((lambda (x) (if x (+ 1 2) 3))")))
    (is (string= result "((lambda (x) (if x (+ 1 2) 3)))"))
    (is (not (null (read-from-string result))))))

(test balance-parens-empty
  (let ((result (opencortex::self-edit-balance-parens "")))
    (is (string= result ""))))

(test test-self-edit-apply-success
  "Verify self-edit-apply performs surgical replacement correctly."
  (let ((test-file "/tmp/self-edit-test.lisp"))
    (unwind-protect
        (progn
          (with-open-file (out test-file :direction :output :if-exists :supersede)
            (write-string "(defun hello () (format t \"world~%\"))" out))
          (let ((result (opencortex::self-edit-apply test-file "world" "universe")))
            (is (eq (getf result :status) :success))
            (let ((content (uiop:read-file-string test-file)))
              (is (search "universe" content))
              (is (not (search "world" content))))))
      (uiop:delete-file-if-exists test-file))))

(test test-self-edit-apply-not-found
  "Verify self-edit-apply returns error when pattern not found."
  (let ((test-file "/tmp/self-edit-test2.lisp"))
    (unwind-protect
        (progn
          (with-open-file (out test-file :direction :output :if-exists :supersede)
            (write-string "(defun hello () t)" out))
          (let ((result (opencortex::self-edit-apply test-file "nonexistent-pattern" "new")))
            (is (eq (getf result :status) :error))
            (is (search "not found" (getf result :message)))))
      (uiop:delete-file-if-exists test-file))))

(test test-self-edit-apply-file-not-found
  "Verify self-edit-apply returns error when file does not exist."
  (let ((result (opencortex::self-edit-apply "/nonexistent/path/file.lisp" "old" "new")))
    (is (eq (getf result :status) :error))
    (is (search "not found" (getf result :message)))))

(test test-self-edit-parse-location-from-payload
  "Verify self-edit-parse-location extracts file/line from payload."
  (let ((context '(:payload (:file "/tmp/test.lisp" :line 42 :message "error"))))
    (let ((result (opencortex::self-edit-parse-location context)))
      (is (equal "/tmp/test.lisp" (getf result :file)))
      (is (eq 42 (getf result :line))))))

(test test-self-edit-parse-location-from-message
  "Verify self-edit-parse-location extracts file/line from error message."
  (let ((context '(:payload (:message "Error in /home/user/project/foo.lisp at line 99"))))
    (let ((result (opencortex::self-edit-parse-location context)))
      (is (listp result))
      (is (getf result :line))
      (is (eq 99 (getf result :line))))))
