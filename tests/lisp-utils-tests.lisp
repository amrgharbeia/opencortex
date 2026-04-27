(defpackage :opencortex-lisp-utils-tests
  (:use :cl :fiveam :opencortex)
  (:export #:lisp-utils-suite))

(in-package :opencortex-lisp-utils-tests)

(def-suite lisp-utils-suite
  :description "Tests for the Lisp Utils skill.")

(in-suite lisp-utils-suite)

;; Character utilities
;; Character utilities
(test count-char-balanced
  (is (= (opencortex::count-char #\( "(+ 1 2)") 1))
  (is (= (opencortex::count-char #\) "(+ 1 2)") 1)))

(test count-char-unbalanced
  (is (= (opencortex::count-char #\( "(+ 1 2") 1))
  (is (= (opencortex::count-char #\) "(+ 1 2") 0)))

(test count-char-empty
  (is (= (opencortex::count-char #\( "") 0)))

;; Deterministic repair
(test deterministic-repair-balanced
  (is (string= (opencortex::deterministic-repair "(+ 1 2)") "(+ 1 2)")))

(test deterministic-repair-unbalanced-open
  (is (string= (opencortex::deterministic-repair "(+ 1 2") "(+ 1 2)")))

(test deterministic-repair-unbalanced-close
  (is (string= (opencortex::deterministic-repair "(+ 1 2))") "(+ 1 2))")))

(test deterministic-repair-empty
  (is (string= (opencortex::deterministic-repair "") "")))

;; Structural check
(test structural-valid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "(+ 1 2)")
    (is (eq ok t))))

(test structural-unbalanced
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "(+ 1 2")
    (is (not ok))
    (is (search "Unbalanced" reason))))

(test structural-mismatched
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "[)")
    (is (not ok))
    (is (search "Mismatched" reason))))

;; Syntactic check
(test syntactic-valid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-syntactic "(+ 1 2)")
    (is (eq ok t))))

(test syntactic-invalid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-syntactic "(1+ 2 #\")")
    (is (not ok))))

;; Semantic check
(test semantic-whitelist-safe
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-semantic "(+ 1 2)")
    (is (eq ok t))))

(test semantic-blocked-eval
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-semantic "(eval '(+ 1 2))")
    (is (not ok))))

(test semantic-blocked-delete
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-semantic "(delete-file \"x.txt\")")
    (is (not ok))))

;; Unified validation
(test unified-success
  (let ((result (opencortex::lisp-utils-validate "(+ 1 2)" :strict t)))
    (is (eq (getf result :status) :success))))

(test unified-structural-fail
  (let ((result (opencortex::lisp-utils-validate "(+ 1 2" :strict nil)))
    (is (eq (getf result :status) :error))
    (is (eq (getf result :failed) :structural))))

(test unified-semantic-fail
  (let ((result (opencortex::lisp-utils-validate "(delete-file \"x.txt\")" :strict t)))
    (is (eq (getf result :status) :error))
    (is (eq (getf result :failed) :semantic))))
