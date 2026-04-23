(defpackage :opencortex-lisp-utils-tests
  (:use :cl :fiveam :opencortex)
  (:export #:lisp-utils-suite))

(in-package :opencortex-lisp-utils-tests)

(def-suite lisp-utils-suite
  :description "Tests for the Lisp Utils skill - utilities, repair, and validation.")

(in-suite lisp-utils-suite)

;; Character utilities
(test count-char-balanced
  (is (= (count-char #\( "(+ 1 2)") 1))
  (is (= (count-char #\) "(+ 1 2)") 1)))

(test count-char-unbalanced
  (is (= (count-char #\( "(+ 1 2") 1))
  (is (= (count-char #\) "(+ 1 2") 0)))

(test count-char-empty
  (is (= (count-char #\( "") 0)))

;; Deterministic repair
(test deterministic-repair-balanced
  (is (string= (deterministic-repair "(+ 1 2)") "(+ 1 2)")))

(test deterministic-repair-unbalanced-open
  (is (string= (deterministic-repair "(+ 1 2") "(+ 1 2)")))

(test deterministic-repair-unbalanced-close
  (is (string= (deterministic-repair "(+ 1 2))") "(+ 1 2)))")) ;; Left as-is (can't fix)

(test deterministic-repair-empty
  (is (string= (deterministic-repair "") "")))

;; ID generation
(test id-generation
  (let ((id1 (emacs-edit-generate-id))
        (id2 (emacs-edit-generate-id)))
    (is (plusp (length id1)))
    (is (not (string= id1 id2))) ;; Likely unique
    (is (= 8 (length id1)))))

(test id-format
  (let ((formatted (emacs-edit-id-format "abc12345")))
    (is (search "id:" formatted))))

;; Structural check (from lisp-utils)
(test structural-valid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "(+ 1 2)")
    (is ok)))

(test structural-unbalanced
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "(+ 1 2")
    (is (not ok))
    (is (search "Unbalanced" reason))))

(test structural-mismatched
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-structural "(let [x 1])")
    (is (not ok))
    (is (search "Mismatched" reason))))

;; Syntactic check
(test syntactic-valid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-syntactic "(+ 1 2)")
    (is ok)))

(test syntactic-invalid
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-syntactic "(1+ 2 #\"")
    (is (not ok))))

;; Semantic check
(test semantic-whitelist-safe
  (multiple-value-bind (ok reason line col)
      (opencortex::lisp-utils-check-semantic "(+ 1 2)")
    (is ok)))

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