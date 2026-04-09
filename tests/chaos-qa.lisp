(defpackage :org-agent-chaos-qa
  (:use :cl :fiveam :org-agent)
  (:export #:chaos-suite))

(in-package :org-agent-chaos-qa)

(def-suite chaos-suite
  :description "Chaos QA: Attempting to break the org-agent kernel.")

(in-suite chaos-suite)

(test malformed-ast-injection
  "Verify that injecting a non-list AST doesn't crash the kernel."
  (kernel-log "CHAOS: Injecting string as AST")
  ;; This should be caught by handler-case in cognitive-loop or perceive
  (let ((malformed-stimulus '(:type :EVENT :payload (:sensor :buffer-update :ast "NOT A LIST"))))
    (finishes (ignore-errors (perceive-gate malformed-stimulus)))
    (finishes (ignore-errors (process-signal malformed-stimulus)))))

(test deep-recursion-stimulus
  "Verify that deep recursion is halted by the recursion breaker."
  (kernel-log "CHAOS: Injecting deep recursion stimulus")
  (clrhash org-agent::*skills-registry*)
  ;; Skill that always triggers another instance of itself
  (org-agent::defskill :infinite-skill
    :priority 100
    :trigger (lambda (ctx) t)
    :neuro (lambda (ctx) nil)
    :symbolic (lambda (action ctx) 
                `(:type :EVENT :payload (:sensor :infinite-trigger))))
  
  ;; The pipeline has (when (> depth 10) ...) check.
  (finishes (process-signal '(:type :EVENT :payload (:sensor :infinite-trigger)))))

(test missing-actuator-dispatch
  "Verify that dispatching to a non-existent actuator is handled."
  (kernel-log "CHAOS: Dispatching to missing actuator")
  (let ((action '(:type :REQUEST :target :ghost-actuator :payload (:action :boo))))
    (finishes (org-agent:dispatch-action action nil))))

(test property-collision-hashing
  "Verify that hash is stable even if properties are sent in different order."
  (let* ((ast1 '(:type :HEADLINE :properties (:ID "collision" :A "1" :B "2") :contents nil))
         (ast2 '(:type :HEADLINE :properties (:ID "collision" :B "2" :A "1") :contents nil)))
    (clrhash org-agent::*object-store*)
    (let ((h1 (org-object-hash (lookup-object (ingest-ast ast1)))))
      (clrhash org-agent::*object-store*)
      (let ((h2 (org-object-hash (lookup-object (ingest-ast ast2)))))
        (is (equal h1 h2))))))
