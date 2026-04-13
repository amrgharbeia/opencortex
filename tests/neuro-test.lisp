(require 'asdf)
(ql:quickload '(:bordeaux-threads :cl-json :dexador :cl-ppcre :uiop))

;; Mock kernel log to prevent spamming stdout during tests
(defpackage :org-agent (:use :cl))
(in-package :org-agent)

;; We need to load the core and probabilistic files to test them.
(load "projects/org-agent/src/core.lisp")
(load "projects/org-agent/src/probabilistic.lisp")

;; Simple testing framework
(defvar *tests-run* 0)
(defvar *tests-passed* 0)

(defmacro assert-equal (expected actual &optional message)
  `(progn
     (incf *tests-run*)
     (let ((e ,expected) (a ,actual))
       (if (equal e a)
           (progn
             (incf *tests-passed*)
             (format t "PASS: ~a~%" (or ,message "Assertion passed")))
           (format t "FAIL: ~a~%  Expected: ~s~%  Got: ~s~%" (or ,message "Assertion failed") e a)))))

(defmacro assert-true (condition &optional message)
  `(progn
     (incf *tests-run*)
     (let ((c ,condition))
       (if c
           (progn
             (incf *tests-passed*)
             (format t "PASS: ~a~%" (or ,message "Assertion passed")))
           (format t "FAIL: ~a~%  Condition evaluated to NIL~%" (or ,message "Assertion failed"))))))

(format t "--- Running Probabilistic Microkernel Tests ---~%")

;; Test 1: Graceful failure on empty registry
(clrhash org-agent::*probabilistic-backends*)
(setf org-agent::*provider-cascade* '(:nonexistent))

(let ((result (org-agent:ask-probabilistic "Test prompt")))
  (assert-true (and (stringp result) (search ":LOG" result) (search "Neural Cascade Failure" result))
               "ask-probabilistic should return a Neural Cascade Failure log when no backends are available."))

;; Test 2: Successful delegation to a mock provider
(defvar *mock-called* nil)
(defun mock-provider-fn (prompt system-prompt &key model)
  (declare (ignore system-prompt model))
  (setf *mock-called* t)
  (format nil "MOCK-RESPONSE: ~a" prompt))

(org-agent:register-probabilistic-backend :mock #'mock-provider-fn)

;; Temporarily mock the token accountant's model selector so it doesn't fail
(defun mock-model-selector (provider context)
  (declare (ignore context))
  "mock-model-v1")
(setf org-agent::*model-selector-fn* #'mock-model-selector)

;; Test with our mock provider
(setf org-agent::*provider-cascade* '(:mock))
(let ((result (org-agent:ask-probabilistic "Hello Mock")))
  (assert-equal "MOCK-RESPONSE: Hello Mock" result "ask-probabilistic should return the exact string from the registered provider")
  (assert-true *mock-called* "The mock provider function must be called by ask-probabilistic"))

;; Test 3: The core should NOT contain execute-openrouter-request, execute-groq-request, or execute-gemini-request
;; This is the architectural test. These functions should be UNBOUND or not exist in the org-agent package.
(assert-true (not (fboundp 'org-agent::execute-openrouter-request))
             "execute-openrouter-request should be removed from the core probabilistic.lisp")
(assert-true (not (fboundp 'org-agent::execute-groq-request))
             "execute-groq-request should be removed from the core probabilistic.lisp")
(assert-true (not (fboundp 'org-agent::execute-gemini-request))
             "execute-gemini-request should be removed from the core probabilistic.lisp")

(format t "--- Test Summary ---~%")
(format t "Tests Run: ~a~%" *tests-run*)
(format t "Tests Passed: ~a~%" *tests-passed*)

(if (= *tests-run* *tests-passed*)
    (uiop:quit 0)
    (uiop:quit 1))
