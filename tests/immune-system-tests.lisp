(defpackage :opencortex-immune-system-tests
  (:use :cl :fiveam :opencortex)
  (:export #:immune-suite))

(in-package :opencortex-immune-system-tests)

(def-suite immune-suite
  :description "Verification of the Immune System (Core Error Hooks)")

(in-suite immune-suite)

(test loop-error-injection
  "Verify that a crash in think/decide triggers a :loop-error stimulus."
  (clrhash opencortex::*skills-registry*)
  (opencortex:defskill :evil-skill
    :priority 100
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :user-input))
    :probabilistic (lambda (ctx) (error "CRITICAL BRAIN FAILURE"))
    :deterministic nil)
  (opencortex:harness-log "CLEAN LOG")
  (opencortex:process-signal '(:type :EVENT :payload (:sensor :user-input)))
  (let ((logs (opencortex:context-get-system-logs 20)))
    (is (not (null (find-if (lambda (line) (search "CRITICAL BRAIN FAILURE" line)) logs))))))
