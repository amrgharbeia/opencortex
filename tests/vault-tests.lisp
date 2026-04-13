(defpackage :org-agent-vault-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-vault-tests)

(def-suite vault-suite :description "Tests for the Credentials Vault.")
(in-suite vault-suite)

(test test-masking
  (is (equal "sk-t...-key" (org-agent::vault-mask-string "sk-test-key")))
  (is (equal "[REDACTED]" (org-agent::vault-mask-string "short"))))

(test test-vault-persistence
  "Verify that setting a secret triggers a snapshot (mock check)."
  (let ((old-version (org-agent::org-object-version (gethash "root" *memory*))))
    (org-agent:vault-set-secret :test "secret-val")
    (is (> (org-agent::org-object-version (gethash "root" *memory*)) old-version))))
