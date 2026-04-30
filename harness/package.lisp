(defpackage :opencortex
  (:use :cl)
  (:export
   ;; --- communication protocol ---
   #:frame-message
   #:read-framed-message
   #:PROTO-GET
   #:LIST-OBJECTS-WITH-ATTRIBUTE
   #:COSINE-SIMILARITY
   #:VAULT-MASK-STRING
   #:*VAULT-MEMORY*
   #:parse-message
   #:make-hello-message
   #:validate-communication-protocol-schema

   ;; --- Daemon Lifecycle ---
   #:start-daemon
   #:stop-daemon
   #:harness-log
   #:main

   ;; --- Diagnostic Doctor ---
   #:doctor-run-all
   #:doctor-main
   #:doctor-check-dependencies
   #:doctor-check-env

   ;; --- Setup Wizard ---
   #:register-provider
   #:system-ready-p
   #:run-setup-wizard

   ;; --- Gateway Manager Skill ---
   #:skill-gateway-register
   #:skill-gateway-link
   #:gateway-manager-main

   ;; --- Memory (CLOSOS) ---
   #:ingest-ast
   #:lookup-object
   #:list-objects-by-type
   #:org-id-new
   #:*memory*
   #:*history-store*
   #:org-object
   #:make-org-object
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
   #:snapshot-memory
   #:rollback-memory

   ;; --- Context API (Peripheral Vision) ---
   #:context-query-store
   #:context-get-active-projects
   #:context-get-recent-completed-tasks
   #:context-list-all-skills
   #:context-get-skill-source
   #:context-get-system-logs
   #:context-resolve-path
   #:context-get-skill-telemetry
   #:harness-track-telemetry
   #:context-assemble-global-awareness

   ;; --- Reactive Signal Pipeline ---
   #:process-signal
   #:perceive-gate
   #:probabilistic-gate
   #:consensus-gate
   #:act-gate
   #:reason-gate
   #:perceive-gate
   #:dispatch-gate
   #:inject-stimulus
   #:initialize-actuators
   #:dispatch-action
   #:register-actuator

   ;; --- Skill Engine ---
   #:load-skill-from-org
   #:initialize-all-skills
   #:load-skill-with-timeout
   #:topological-sort-skills
   #:validate-lisp-syntax
   #:defskill
   #:*skills-registry*
   #:skill
   #:skill-name
   #:skill-priority
   #:skill-dependencies
   #:skill-trigger-fn
   #:skill-probabilistic-prompt
   #:skill-deterministic-fn

   ;; --- Tool Registry ---
   #:def-cognitive-tool
   #:*cognitive-tools*

   ;; --- Engineering Standards Skill ---
   #:verify-git-clean-p
   #:engineering-standards-verify-lisp
   #:engineering-standards-format-lisp

   ;; --- Literate Programming Skill ---
   #:literate-check-block-balance
   #:check-tangle-sync
   #:*tangle-targets*

   ;; --- Utils Org Skill ---
   #:utils-org-read-file
   #:utils-org-write-file
   #:utils-org-add-headline
   #:utils-org-set-property
   #:utils-org-set-todo
   #:utils-org-find-headline-by-id
   #:utils-org-find-headline-by-title
   #:utils-org-generate-id
   #:utils-org-id-format
   #:utils-org-ast-to-org
   #:utils-org-modify

   ;; --- Utils Lisp Skill ---
   #:utils-lisp-validate
   #:utils-lisp-check-structural
   #:utils-lisp-check-syntactic
   #:utils-lisp-check-semantic
   #:utils-lisp-eval
   #:utils-lisp-format
   #:utils-lisp-list-definitions
   #:utils-lisp-structural-extract
   #:utils-lisp-structural-wrap
   #:utils-lisp-structural-inject
   #:utils-lisp-structural-slurp
   #:utils-lisp-register

   ;; --- Config Manager & Diagnostics Skill ---
   #:get-oc-config-dir
   #:prompt-for
   #:save-secret

   ;; --- Tool Permissions Skill ---
   #:get-tool-permission
   #:set-tool-permission
   #:check-tool-permission-gate
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

   ;; --- Probabilistic Engine ---
   #:ask-probabilistic
   #:register-probabilistic-backend
   #:distill-prompt
   #:*provider-cascade*

   ;; --- Security Vault ---
   #:vault-get-secret
   #:vault-set-secret

   ;; --- Deterministic Logic ---
   #:list-objects-with-attribute
   #:deterministic-verify

   ;; --- AST Helpers ---
   #:find-headline-missing-id))

(in-package :opencortex)

(defun proto-get (plist key)
  "Robustly retrieves a value from a plist, checking both uppercase and lowercase keyword versions."
  (let* ((s (string key))
         (up (intern (string-upcase s) :keyword))
         (dn (intern (string-downcase s) :keyword)))
    (or (getf plist up) (getf plist dn))))

(defvar *system-logs* nil)
(defvar *logs-lock* (bordeaux-threads:make-lock "harness-logs-lock"))
(defvar *max-log-history* 100)

(defvar *skills-registry* (make-hash-table :test 'equal)
  "Global registry of all loaded skills.")

(defvar *skill-telemetry* (make-hash-table :test 'equal))
(defvar *telemetry-lock* (bordeaux-threads:make-lock "harness-telemetry-lock"))

(defun harness-track-telemetry (skill-name duration status)
  "Updates performance metrics for a specific skill. Status should be :success or :rejected."
  (when skill-name
    (bordeaux-threads:with-lock-held (*telemetry-lock*)
      (let ((entry (or (gethash skill-name *skill-telemetry*) (list :executions 0 :total-time 0 :failures 0))))
        (incf (getf entry :executions))
        (incf (getf entry :total-time) duration)
        (when (eq status :rejected) (incf (getf entry :failures)))
        (setf (gethash skill-name *skill-telemetry*) entry)))))

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
    (bordeaux-threads:with-lock-held (*logs-lock*)
      (push formatted-msg *system-logs*)
      (when (> (length *system-logs*) *max-log-history*)
        (setq *system-logs* (subseq *system-logs* 0 *max-log-history*))))
    (format t "~a~%" formatted-msg)
    (finish-output)))

;; --- Debugger Hook ---
(setf *debugger-hook* (lambda (condition hook)
  "Friendly error handler - shows diagnostic message instead of raw debugger."
  (format t "~%")
  (format t "┌─────────────────────────────────────────────┐~%")
  (format t "│  ERROR: ~A~%" (type-of condition))
  (format t "│~%")
  (format t "│  Run: opencortex doctor~%")
  (format t "│  For system diagnostics~%")
  (format t "└─────────────────────────────────────────────┘~%")
  (format t "~%")
  (format t "Details: ~A~%" condition)
  (finish-output)
  (uiop:quit 1)))
