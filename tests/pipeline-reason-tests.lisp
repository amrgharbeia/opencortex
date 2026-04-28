(defpackage :opencortex-pipeline-reason-tests
  (:use :cl :fiveam :opencortex)
  (:export #:pipeline-reason-suite))

(in-package :opencortex-pipeline-reason-tests)

(def-suite pipeline-reason-suite
  :description "Test suite for Reason pipeline")

(in-suite pipeline-reason-suite)

(test test-decide-gate-safety
  "Decide gate should block unsafe LLM proposals."
  ;; Setup: clear skills and register mock
  (clrhash opencortex::*skills-registry*)
  (opencortex::defskill :mock-safety
    :priority 50
    :trigger (lambda (ctx) t)
    :probabilistic (lambda (ctx) "Mock probabilistic")
    :deterministic (lambda (action ctx)
                (list :type :LOG :payload (list :text "Action rejected by skill heuristics"))))
  (let* ((candidate (list :type :REQUEST :payload (list :action :eval :code "(shell-command \"rm -rf /\")")))
         (signal (list :type :EVENT :candidate candidate))
         (result (deterministic-verify candidate signal)))
    (is (eq :LOG (getf result :type)))
    (is (search "Action rejected by skill heuristics" (getf (getf result :payload) :text)))))
