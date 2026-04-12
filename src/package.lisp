(defpackage :org-agent
  (:use :cl)
  (:export 
   ;; --- Harness Protocol ---
   #:frame-message
   #:parse-message
   #:make-hello-message
   #:validate-harness-protocol-schema
   
   ;; --- Daemon Lifecycle ---
   #:start-daemon
   #:stop-daemon
   #:harness-log
   #:main
   
   ;; --- Object Store (CLOSOS) ---
   #:ingest-ast
   #:lookup-object
   #:list-objects-by-type
   #:*object-store*
   #:*history-store*
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
   
   ;; --- Context API (Peripheral Vision) ---
   #:context-query-store
   #:context-get-active-projects
   #:context-get-recent-completed-tasks
   #:context-list-all-skills
   #:context-get-skill-source
   #:context-get-system-logs
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
   
   ;; --- Skill Engine ---
   #:load-skill-from-org
   #:initialize-all-skills
   #:load-skill-with-timeout
   #:topological-sort-skills
   #:validate-lisp-syntax
   #:safety-harness-validate
   #:defskill
   #:*skills-registry*
   #:skill
   #:skill-name
   #:skill-priority
   #:skill-dependencies
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

   ;; --- Associative Engine ---
   #:ask-neuro
   #:register-neuro-backend
   #:distill-prompt
   #:*provider-cascade*
   
   ;; --- Symbolic Logic ---
   #:list-objects-with-attribute
   #:decide
   
   ;; --- AST Helpers ---
   #:find-headline-missing-id))

(in-package :org-agent)

(defvar *system-logs* nil)
(defvar *logs-lock* (bt:make-lock "harness-logs-lock"))
(defvar *max-log-history* 100)

(defvar *skills-registry* (make-hash-table :test 'equal)
  "Global registry of all loaded skills.")

(defvar *skill-telemetry* (make-hash-table :test 'equal))
(defvar *telemetry-lock* (bt:make-lock "harness-telemetry-lock"))

(defvar *cognitive-tools* (make-hash-table :test 'equal))

(defstruct cognitive-tool
  name
  description
  parameters
  guard
  body)

(defmacro def-cognitive-tool (name description parameters &key guard body)
  "Registers a new cognitive tool into the global registry. Parameters must be a list of property lists."
  `(setf (gethash (string-downcase (string ',name)) *cognitive-tools*)
         (make-cognitive-tool :name (string-downcase (string ',name))
                              :description ,description
                              :parameters ',parameters
                              :guard ,guard
                              :body ,body)))

(defun harness-log (msg &rest args)
  "Centralized logging for the harness."
  (let ((formatted-msg (apply #'format nil msg args)))
    (bt:with-lock-held (*logs-lock*)
      (push formatted-msg *system-logs*)
      (when (> (length *system-logs*) *max-log-history*)
        (setq *system-logs* (subseq *system-logs* 0 *max-log-history*))))
    (format t "~a~%" formatted-msg)
    (finish-output)))
