(defpackage :opencortex-utils-lisp-tests
  (:use :cl :fiveam :opencortex)
  (:export #:utils-lisp-suite))

(in-package :opencortex-utils-lisp-tests)

(def-suite utils-lisp-suite
  :description "Tests for the Lisp Validator structural, syntactic, and semantic gates")

(in-suite utils-lisp-suite)

(test structural-balanced
  (is (eq t (opencortex:utils-lisp-check-structural "(+ 1 2)"))))

(test structural-unbalanced-open
  (multiple-value-bind (ok reason) (opencortex:utils-lisp-check-structural "(+ 1 2")
    (is (null ok))
    (is (search "Reader Error" reason))))

(test structural-unbalanced-close
  (multiple-value-bind (ok reason) (opencortex:utils-lisp-check-structural "+ 1 2)")
    (is (null ok))
    (is (search "Reader Error" reason))))

(test syntactic-valid
  (is (eq t (opencortex:utils-lisp-check-syntactic "(+ 1 2)"))))

(test semantic-safe
  (is (eq t (opencortex:utils-lisp-check-semantic "(+ 1 2)"))))

(test semantic-blocked-eval
  (multiple-value-bind (ok reason) (opencortex:utils-lisp-check-semantic "(eval '(+ 1 2))")
    (is (null ok))
    (is (search "Unsafe" reason))))

(test unified-success
  (let ((result (opencortex:utils-lisp-validate "(+ 1 2)" :strict t)))
    (is (eq (getf result :status) :success))))

(test unified-failure
  (let ((result (opencortex:utils-lisp-validate "(+ 1 2" :strict nil)))
    (is (eq (getf result :status) :error))))

(test eval-basic
  (let ((result (opencortex:utils-lisp-eval "(+ 1 2)")))
    (is (eq (getf result :status) :success))
    (is (string= (getf result :result) "3"))))

(test structural-extract
  (let* ((code "(defun hello () (print \"hi\")) (defun bye () (print \"bye\"))")
         (extracted (opencortex:utils-lisp-structural-extract code "hello")))
    (is (not (null extracted)))
    (let ((form (read-from-string extracted)))
      (is (eq (car form) 'DEFUN))
      (is (eq (second form) 'HELLO)))))

(test list-definitions
  (let ((code "(defun foo () t) (defmacro bar () nil) (defparameter *baz* 10)"))
    (let ((names (opencortex:utils-lisp-list-definitions code)))
      (is (member 'FOO names))
      (is (member 'BAR names))
      (is (member '*BAZ* names)))))

(test structural-inject
  (let* ((code "(defun my-fun (x) (print x))")
         (injected (opencortex:utils-lisp-structural-inject code "my-fun" "(finish-output)")))
    (let ((form (read-from-string injected)))
      (is (equal (last form) '((FINISH-OUTPUT)))))))

(test structural-slurp
  (let* ((code "(defun work () (step-1))")
         (slurped (opencortex:utils-lisp-structural-slurp code "work" "(step-2)")))
    (let ((form (read-from-string slurped)))
      (is (equal (last form) '((STEP-2)))))))
