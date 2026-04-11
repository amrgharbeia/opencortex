(defpackage :org-agent-lisp-repair-tests
  (:use :cl :fiveam :org-agent)
  (:export #:lisp-repair-suite))
(in-package :org-agent-lisp-repair-tests)

(def-suite lisp-repair-suite :description "Tests for Lisp Repair Syntax Gate.")
(in-suite lisp-repair-suite)

(test test-deterministic-repair-balance
  "Verify that deterministic-repair balances parentheses."
  (let ((broken "(:type :REQUEST :target :emacs"))
    (is (equal "(:type :REQUEST :target :emacs)" 
               (org-agent:deterministic-repair broken)))))

(test test-deterministic-repair-deep-balance
  "Verify that deterministic-repair balances multiple nested parentheses."
  (let ((broken "(list :a (list :b 1"))
    (is (equal "(list :a (list :b 1))" 
               (org-agent:deterministic-repair broken)))))

(test test-repair-lisp-syntax-entry
  "Verify that repair-lisp-syntax successfully repairs and parses broken Lisp."
  (let ((broken "(:type :REQUEST :target :tool")
        (error-msg "End of file while reading"))
    (let ((result (org-agent:repair-lisp-syntax broken error-msg)))
      (is (listp result))
      (is (eq :REQUEST (getf result :type)))
      (is (eq :tool (getf result :target))))))
