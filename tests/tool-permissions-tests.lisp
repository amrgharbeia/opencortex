(defpackage :opencortex-tool-permissions-tests
  (:use :cl :fiveam :opencortex)
  (:export #:tool-permissions-suite))

(in-package :opencortex-tool-permissions-tests)

(def-suite tool-permissions-suite
  :description "Tests for Tool Permission Tiers.")

(in-suite tool-permissions-suite)

(test default-permission-is-allow
  "Unknown tools default to :allow."
  (is (eq (get-tool-permission :unknown-tool-xyz) :allow)))

(test set-and-get-permission
  "Verify :allow, :deny, :ask persist correctly."
  (set-tool-permission :test-tool-abc :deny)
  (is (eq (get-tool-permission :test-tool-abc) :deny))
  (set-tool-permission :test-tool-abc :ask)
  (is (eq (get-tool-permission :test-tool-abc) :ask))
  (set-tool-permission :test-tool-abc :allow)
  (is (eq (get-tool-permission :test-tool-abc) :allow)))

(test permission-gate-allow
  ":allow returns :allow."
  (set-tool-permission :gate-allow-tool :allow)
  (is (eq (check-tool-permission-gate :gate-allow-tool nil) :allow)))

(test permission-gate-deny
  ":deny returns :deny."
  (set-tool-permission :gate-deny-tool :deny)
  (is (eq (check-tool-permission-gate :gate-deny-tool nil) :deny)))

(test permission-gate-ask
  ":ask returns a signal list."
  (set-tool-permission :gate-ask-tool :ask)
  (let ((result (check-tool-permission-gate :gate-ask-tool nil)))
    (is (listp result))
    (is (eq (car result) :ask))))