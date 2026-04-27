(defpackage :opencortex-lisp-validator-tests
  (:use :cl :fiveam :opencortex)
  (:export #:lisp-validator-suite))

(in-package :opencortex-lisp-validator-tests)

(def-suite lisp-validator-suite
  :description "Tests for the Lisp Validator structural, syntactic, and semantic gates")

(in-suite lisp-validator-suite)

(test structural-balanced
  (let ((result (opencortex::lisp-validator-check-structural "(+ 1 2)")))
    (is (eq result t))))

(test structural-unbalanced-open
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-structural "(+ 1 2")
    (is (null ok))
    (is (search "Unbalanced" reason))))

(test structural-unbalanced-close
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-structural "+ 1 2)")
    (is (null ok))
    (is (search "Unbalanced" reason))))

(test syntactic-valid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-syntactic "(+ 1 2)")
    (is (eq ok t))))

(test syntactic-invalid-reader
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-syntactic "(1+ 2 #\")")
    (is (not ok))))

(test semantic-safe
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-semantic "(+ 1 2)")
    (is (eq ok t))))

(test semantic-blocked-eval
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-validator-check-semantic "(eval '(+ 1 2))")
    (is (not ok))))

(test unified-success
  (let ((result (opencortex::lisp-validator-validate "(+ 1 2)" :strict t)))
    (is (eq (getf result :status) :success))))

(test unified-failure
  (let ((result (opencortex::lisp-validator-validate "(+ 1 2" :strict nil)))
    (is (eq (getf result :status) :error))))
