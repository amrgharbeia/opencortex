(defpackage :org-agent-cognitive-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-cognitive-tests)

(def-suite cognitive-suite
  :description "Verification of the Perceive-Think-Decide-Act loop.")
(in-suite cognitive-suite)

(defun setup-mock-skills ()
  "Register mock skills for testing."
  (clrhash org-agent::*skills-registry*)
  
  (org-agent::defskill :mock-refactor
    :priority 100
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :command) :organize-subtree))
    :neuro (lambda (ctx) "Mock neuro prompt")
    :symbolic (lambda (action ctx) 
                `(:type :REQUEST :id 123 
                  :payload (:action :refactor-subtree 
                            :target-id nil 
                            :properties (("ID" . "node-123"))))))

  (org-agent::defskill :mock-safety
    :priority 50
    :trigger (lambda (ctx) t) ; always triggers
    :neuro (lambda (ctx) "Mock neuro")
    :symbolic (lambda (action ctx) nil))) ; rejects everything

(test test-perceive-ingestion
  "Perceive should update the object store and return context."
  (clrhash org-agent::*object-store*)
  (let* ((stimulus '(:type :EVENT :payload (:sensor :buffer-update :ast (:type :HEADLINE :properties (:ID "test-node" :TITLE "Test") :contents nil))))
         (context (perceive stimulus)))
    (is (equal stimulus context))
    (is (not (null (gethash "test-node" org-agent::*object-store*))))))

(test test-decide-safety-gate
  "Decide should block unsafe LLM proposals (System 2 bouncer)."
  (setup-mock-skills)
  (let ((context '(:type :EVENT :payload (:sensor :buffer-update)))
        (unsafe-proposal '(:type :REQUEST :payload (:action :eval :code "(shell-command \"rm -rf /\")"))))
    (let ((decision (decide unsafe-proposal context)))
      (is (eq :LOG (getf decision :type)))
      (is (search "Action rejected by skill heuristics" (getf (getf decision :payload) :text))))))

(test test-decide-deterministic-override
  "Decide should pre-empt LLM for deterministic tasks like missing IDs."
  (setup-mock-skills)
  (let* ((ast '(:type :HEADLINE :properties (:TITLE "No ID") :contents nil))
         (context `(:type :EVENT :payload (:sensor :user-command :command :organize-subtree :ast ,ast)))
         (dummy-proposal '(:type :LOG :payload (:text "I am thinking..."))))
    (let ((decision (decide dummy-proposal context)))
      (is (eq :REQUEST (getf decision :type)))
      (is (eq :refactor-subtree (getf (getf decision :payload) :action)))
      (is (not (null (assoc "ID" (getf (getf decision :payload) :properties) :test #'string=)))))))

(test test-env-loading
  "Verify that environment variables are accessible (Phase 2 gating)."
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
  ;; Add a dependent skill
  (org-agent::defskill :mock-dependent
    :priority 10
    :dependencies '("mock-safety")
    :trigger (lambda (ctx) nil)
    :neuro nil
    :symbolic nil)
  (let ((deps (org-agent::resolve-skill-dependencies "mock-dependent")))
    (is (member "mock-safety" deps :test #'string-equal))
    (is (member "mock-dependent" deps :test #'string-equal))))

(test test-log-buffering
  "Verify that kernel-log correctly populates the system logs."
  (kernel-log "PSF TEST LOG")
  (let ((logs (context-get-system-logs 5)))
    (is (cl:some (lambda (line) (search "PSF TEST LOG" line)) logs))))

(test test-global-awareness-assembly
  "Verify that context-assemble-global-awareness reports active projects."
  (clrhash org-agent::*object-store*)
  ;; Ingest a project node
  (ingest-ast '(:type :HEADLINE :properties (:ID "proj-1" :TITLE "Project Alpha" :TAGS "project") :contents nil))
  ;; Ingest a non-project node
  (ingest-ast '(:type :HEADLINE :properties (:ID "note-1" :TITLE "Random Note") :contents nil))
  
  (let ((awareness (context-assemble-global-awareness)))
    (is (search "Project Alpha" awareness))
    (is (search "proj-1" awareness))
    (is (not (search "Random Note" awareness)))))
