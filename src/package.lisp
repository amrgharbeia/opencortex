(defpackage :org-agent
  (:use :cl)
  (:export 
   ;; --- OACP Protocol ---
   #:frame-message
   #:parse-message
   #:make-hello-message
   
   ;; --- Daemon Lifecycle ---
   #:start-daemon
   #:stop-daemon
   #:kernel-log
   #:main
   
   ;; --- Object Store (CLOSOS) ---
   #:ingest-ast
   #:lookup-object
   #:list-objects-by-type
   #:*object-store*
   #: *history-store*
   #:org-object
   #:org-object-id
   #:org-object-type
   #:org-object-attributes
   #:org-object-parent-id
   #:org-object-children
   #:org-object-version
   #:org-object-last-sync
   #:org-object-vector
   #:org-object-content
   #:org-object-hash
   #:snapshot-object-store
   #:rollback-object-store
   #:send-swarm-packet
   
   ;; --- Self-Fix Agent ---
   #:self-fix-apply
   
   ;; --- Context API (Peripheral Vision) ---
   #:context-query-store
   #:context-get-active-projects
   #:context-get-recent-completed-tasks
   #:context-list-all-skills
   #:context-get-skill-source
   #:context-get-system-logs
   #:context-filter-sparse-tree
   #:context-resolve-path
   #:context-get-skill-telemetry
   #:context-assemble-global-awareness
   
   ;; --- Reactive Signal Pipeline ---
   #:process-signal
   #:perceive-gate
   #:neuro-gate
   #:consensus-gate
   #:decide-gate
   #:dispatch-gate
   #:inject-stimulus
   #:dispatch-action
   #:register-actuator
   #:spawn-task
   
   ;; --- Skill Engine ---
   #:load-skill-from-org
   #:initialize-all-skills
   #:load-skill-with-timeout
   #:topological-sort-skills
   #:validate-lisp-syntax
   #:safety-harness-validate
   #:find-triggered-skill
   #:defskill
   #:*skills-registry*
   #:skill
   #:skill-name
   #:skill-priority
   #:skill-trigger-fn
   #:skill-neuro-prompt
   #:skill-symbolic-fn

   ;; --- Tool Registry ---
   #:def-cognitive-tool
   #:*cognitive-tools*
   #:cognitive-tool
   #:cognitive-tool-name
   #:cognitive-tool-description
   #:cognitive-tool-parameters
   #:cognitive-tool-guard
   #:cognitive-tool-body

   ;; --- Emacs Client Registry ---
   #:*emacs-clients*
   #:*clients-lock*
   #:register-emacs-client
   #:unregister-emacs-client

   ;; --- Neuro (System 1) ---

   #:ask-neuro
   #:register-neuro-backend
   #:register-auth-provider
   #:get-provider-auth
   #:distill-prompt
   #:get-embedding
   #:cosine-similarity
   #:find-most-similar
   #:openrouter-get-available-models
   #:*provider-cascade*
   #:token-accountant-route-task
   
   ;; --- Symbolic Logic ---
   #:list-objects-with-attribute
   #:org-id-new
   
   ;; --- AST Helpers ---
   #:find-headline-missing-id
   
   ;; --- Environment Config ---
   #:set-llm-model
   #:get-llm-model))
