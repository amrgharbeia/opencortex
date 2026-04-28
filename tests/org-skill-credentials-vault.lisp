#|
(defpackage :opencortex-vault-tests
  (:use :cl :fiveam :opencortex))
(in-package :opencortex-vault-tests)

(def-suite vault-suite :description "Tests for the Credentials Vault.")
(in-suite vault-suite)

(test test-masking
  (is (equal "sk-t...-key" (opencortex::vault-mask-string "sk-test-key")))
  (is (equal "[REDACTED]" (opencortex::vault-mask-string "short"))))

(test test-vault-persistence
  "Verify that setting a secret triggers a snapshot (mock check)."
  (let ((old-version (opencortex::org-object-version (gethash "root" *memory*))))
    (opencortex:vault-set-secret :test "secret-val")
    (is (> (opencortex::org-object-version (gethash "root" *memory*)) old-version))))
|#
