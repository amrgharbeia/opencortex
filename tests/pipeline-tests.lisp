(defpackage :org-agent-pipeline-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-pipeline-tests)

(def-suite pipeline-suite
  :description "Verification of the Reactive Signal Pipeline.")
(in-suite pipeline-suite)

(defun setup-mock-skills ()
  "Register mock skills for testing."
  (clrhash org-agent::*skills-registry*)
  (org-agent::defskill :mock-refactor
    :priority 100
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :command) :organize-subtree))
    :probabilistic (lambda (ctx) "Mock probabilistic prompt")
    :deterministic (lambda (action ctx) 
                `(:type :REQUEST :id 123 
                  :payload (:action :refactor-subtree 
                            :target-id nil 
                            :properties (("ID" . "node-123"))))))
  (org-agent::defskill :mock-safety
    :priority 50
    :trigger (lambda (ctx) t) ; always triggers
    :probabilistic (lambda (ctx) "Mock probabilistic")
    :deterministic (lambda (action ctx) nil))) ; rejects everything

(test test-perceive-gate
  "Perceive gate should update the object store and normalize signal."
  (clrhash org-agent::*memory*)
  (let* ((signal (list :type :EVENT :payload (list :sensor :buffer-update :ast (list :type :HEADLINE :properties (list :ID "test-node" :TITLE "Test") :contents nil))))
         (result (perceive-gate signal)))
    (is (eq :perceived (getf result :status)))
    (is (not (null (gethash "test-node" org-agent::*memory*))))))

(test test-decide-gate-safety
  "Decide gate should block unsafe LLM proposals."
  (setup-mock-skills)
  (let* ((candidate (list :type :REQUEST :payload (list :action :eval :code "(shell-command \"rm -rf /\")")))
         (signal (list :type :EVENT :candidate candidate))
         (result (decide-gate signal)))
    (is (eq :decided (getf result :status)))
    (let ((approved (getf result :approved-action)))
      (is (eq :LOG (getf approved :type)))
      (is (search "Action rejected by skill heuristics" (getf (getf approved :payload) :text))))))

(test test-pipeline-flow-flat
  "Verify that process-signal correctly executes a signal through gates."
  (setup-mock-skills)
  (clrhash org-agent::*memory*)
  (let ((signal (list :type :EVENT :payload (list :sensor :buffer-update))))
    (process-signal signal)
    (pass "Pipeline completed execution.")))

(test test-depth-limiting
  "Verify that the pipeline terminates runaway feedback loops."
  (let ((runaway-signal (list :type :EVENT :depth 11 :payload (list :sensor :heartbeat))))
    (is (null (process-signal runaway-signal)))))

(test test-env-loading
  "Verify that environment variables are accessible."
  (setf (uiop:getenv "LLM_ENDPOINT") "http://mock")
  (setf (uiop:getenv "MEMEX_USER") "Amr")
  (is (not (null (uiop:getenv "LLM_ENDPOINT"))))
  (is (stringp (org-agent::get-env "MEMEX_USER"))))

(test test-path-resolution
  "Verify that context-resolve-path expands environment variables."
  (setf (uiop:getenv "MEMEX_USER") "Amr")
  (let ((path "$MEMEX_USER/test"))
    (is (search "Amr/test" (context-resolve-path path)))))

(test test-skill-dependencies
  "Verify that resolve-skill-dependencies correctly flattens the graph."
  (setup-mock-skills)
  (org-agent::defskill :mock-dependent
    :priority 10
    :dependencies (list "mock-safety")
    :trigger (lambda (ctx) nil)
    :probabilistic nil
    :deterministic nil)
  (let ((deps (org-agent::resolve-skill-dependencies "mock-dependent")))
    (is (member "mock-safety" deps :test #'string-equal))
    (is (member "mock-dependent" deps :test #'string-equal))))

(test test-log-buffering
  "Verify that harness-log correctly populates the system logs."
  (harness-log "Engineering TEST LOG")
  (let ((logs (context-get-system-logs 5)))
    (is (cl:some (lambda (line) (search "Engineering TEST LOG" line)) logs))))

(test test-global-awareness-assembly
  "Verify that context-assemble-global-awareness reports active projects."
  (clrhash org-agent::*memory*)
  (ingest-ast (list :type :HEADLINE :properties (list :ID "proj-1" :TITLE "Project Alpha" :TAGS "project") :contents nil))
  (let ((awareness (context-assemble-global-awareness)))
    (is (search "Project Alpha" awareness))
    (is (search "proj-1" awareness))))

(test test-micro-rollback
  "Verify that a pipeline crash triggers an automatic Memory rollback."
  (clrhash org-agent::*memory*)
  (clrhash org-agent::*history-store*)
  (setf org-agent::*object-store-snapshots* nil)
  ;; State A
  (ingest-ast (list :type :HEADLINE :properties (list :ID "node-1" :TITLE "State A") :contents nil))
  (setup-mock-skills)
  (org-agent::defskill :crashing-skill
    :priority 200
    :trigger (lambda (ctx) t)
    :probabilistic (lambda (ctx) (list :type :REQUEST :payload (list :action :eval :code "(error \"BOOM\")")))
    :deterministic (lambda (action ctx) (error "CRASH IN DETERMINISTIC ENGINE")))
  (process-signal (list :type :EVENT :payload (list :sensor :test)))
  ;; Verify that we are still in State A
  (let ((obj (lookup-object "node-1")))
    (is (not (null obj)))
    (is (equal (getf (org-object-attributes obj) :TITLE) "State A"))))
