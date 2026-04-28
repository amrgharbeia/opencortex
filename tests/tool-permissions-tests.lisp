(defpackage :opencortex-tool-permissions-tests
  (:use :cl :fiveam :opencortex)
  (:export #:tool-permissions-suite))

(in-package :opencortex-tool-permissions-tests)

(def-suite tool-permissions-suite
  :description "Tests for Tool Permissions skill")

(in-suite tool-permissions-suite)

(test default-permission-is-allow
  "Verify default permission is :allow."
  (is (eq (get-tool-permission "unknown-tool") :allow)))

(test set-and-get-permission
  "Verify setting and getting permissions."
  (set-tool-permission "test-tool-abc" :deny)
  (is (eq (get-tool-permission "test-tool-abc") :deny)))

(test permission-gate-allow
  "Verify :allow tier passes through."
  (set-tool-permission "gate-allow-tool" :allow)
  (is (eq (check-tool-permission-gate "gate-allow-tool" nil) :allow)))

(test permission-gate-deny
  "Verify :deny tier blocks."
  (set-tool-permission "gate-deny-tool" :deny)
  (is (eq (check-tool-permission-gate "gate-deny-tool" nil) :deny)))

(test permission-gate-ask
  "Verify :ask tier returns ask list."
  (set-tool-permission "gate-ask-tool" :ask)
  (is (listp (check-tool-permission-gate "gate-ask-tool" nil))))
