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
   #:org-object
   #:org-object-id
   #:org-object-type
   #:org-object-attributes
   #:org-object-children
   #:org-object-vector
   #:snapshot-object-store
   #:rollback-object-store
   #:send-swarm-packet
   
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
   
   ;; --- Cognitive Loop & Event Bus ---
   #:perceive
   #:think
   #:decide
   #:act
   #:cognitive-loop
   #:inject-stimulus
   #:dispatch-action
   #:register-actuator
   
   ;; --- Skill Engine ---
   #:load-skill-from-org
   #:validate-lisp-syntax
   #:find-triggered-skill
   #:defskill
   #:*skills-registry*
   #:skill
   #:skill-name
   #:skill-priority
   #:skill-trigger-fn
   #:skill-neuro-prompt
   #:skill-symbolic-fn
   
   ;; --- Neuro (System 1) ---
   #:ask-neuro
   #:register-neuro-backend
   #:register-auth-provider
   #:distill-prompt
   #:get-embedding
   #:cosine-similarity
   #:find-most-similar
   
   ;; --- AST Helpers ---
   #:find-headline-missing-id))
