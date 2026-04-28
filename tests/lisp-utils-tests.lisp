(defpackage :opencortex-lisp-utils-tests
  (:use :cl :fiveam :opencortex)
  (:export #:lisp-utils-suite))

(in-package :opencortex-lisp-utils-tests)

(def-suite lisp-utils-suite
  :description "Tests for the Lisp Validator structural, syntactic, and semantic gates")

(in-suite lisp-utils-suite)

(test structural-balanced
  (is (eq t (opencortex:lisp-utils-check-structural "(+ 1 2)"))))

(test structural-unbalanced-open
  (multiple-value-bind (ok reason) (opencortex:lisp-utils-check-structural "(+ 1 2")
    (is (null ok))
    (is (search "Unbalanced" reason))))

(test structural-unbalanced-close
  (multiple-value-bind (ok reason) (opencortex:lisp-utils-check-structural "+ 1 2)")
    (is (null ok))
    (is (search "Unexpected" reason))))

(test syntactic-valid
  (is (eq t (opencortex:lisp-utils-check-syntactic "(+ 1 2)"))))

(test semantic-safe
  (is (eq t (opencortex:lisp-utils-check-semantic "(+ 1 2)"))))

(test semantic-blocked-eval
  (multiple-value-bind (ok reason) (opencortex:lisp-utils-check-semantic "(eval '(+ 1 2))")
    (is (null ok))
    (is (search "Unsafe" reason))))

(test unified-success
  (let ((result (opencortex:lisp-utils-validate "(+ 1 2)" :strict t)))
    (is (eq (getf result :status) :success))))

(test unified-failure
  (let ((result (opencortex:lisp-utils-validate "(+ 1 2" :strict nil)))
    (is (eq (getf result :status) :error))))
