(defpackage :opencortex-self-edit-tests
  (:use :cl :fiveam :opencortex)
  (:export #:self-edit-suite))

(in-package :opencortex-self-edit-tests)

(def-suite self-edit-suite
  :description "Tests for Self-Edit skill.")

(in-suite self-edit-suite)

(test balance-parens-balanced
  (let ((result (opencortex:self-edit-balance-parens "(+ 1 2)")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-missing-open
  (let ((result (opencortex:self-edit-balance-parens "+ 1 2)")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-missing-close
  (let ((result (opencortex:self-edit-balance-parens "(+ 1 2")))
    (is (string= result "(+ 1 2)"))
    (is (not (null (read-from-string result))))))

(test balance-parens-deep
  (let ((result (opencortex:self-edit-balance-parens "((lambda (x) (if x (+ 1 2) 3))")))
    (is (string= result "((lambda (x) (if x (+ 1 2) 3)))"))
    (is (not (null (read-from-string result))))))

(test balance-parens-empty
  (let ((result (opencortex:self-edit-balance-parens "")))
    (is (string= result ""))))
