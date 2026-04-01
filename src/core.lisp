(in-package :org-agent)

;;; ============================================================================
;;; Internal Logging (The Kernel's Senses)
;;; ============================================================================

(defvar *system-logs* nil
  "A thread-safe circular buffer of recent kernel activity.")
(defvar *logs-lock* (bt:make-lock "kernel-logs-lock"))
(defvar *max-log-history* 100
  "Maximum number of log entries to retain in memory.")

(defvar *skill-telemetry* (make-hash-table :test 'equal)
  "Thread-safe storage for skill performance metrics.")
(defvar *telemetry-lock* (bt:make-lock "kernel-telemetry-lock"))

(defun kernel-track-telemetry (skill-name duration status)
  "Records the execution time and result status of a skill."
  (when skill-name
    (bt:with-lock-held (*telemetry-lock*)
      (let ((entry (or (gethash skill-name *skill-telemetry*)
                       (list :executions 0 :total-time 0 :failures 0))))
        (incf (getf entry :executions))
        (incf (getf entry :total-time) duration)
        (when (eq status :rejected) (incf (getf entry :failures)))
        (setf (gethash skill-name *skill-telemetry*) entry)))))

(defun kernel-log (fmt &rest args)
  "Logs a message to both standard output and the internal circular buffer."
  (let ((msg (apply #'format nil fmt args)))
    (bt:with-lock-held (*logs-lock*)
      (push msg *system-logs*)
      ;; Enforce maximum history length
      (when (> (length *system-logs*) *max-log-history*)
        (setf *system-logs* (subseq *system-logs* 0 *max-log-history*))))
    ;; Mirror to stdout for Docker/Console monitoring
    (format t "~a~%" msg)
    (finish-output)))

;;; ============================================================================
;;; The Autonomic Heartbeat
;;; ============================================================================

(defvar *heartbeat-thread* nil
  "The background thread that provides temporal awareness.")

;;; ============================================================================
;;; The Actuator API (Event Bus)
;;; ============================================================================
;;; The Core Daemon acts as a decoupled Event Bus. Sensors (like Emacs or 
;;; Cron) inject stimuli, and Actuators (like the Emacs Bridge) execute 
;;; the resulting decisions.

(defvar *actuator-registry* (make-hash-table :test 'equal)
  "Registry of loaded actuators. Key is a keyword (e.g., :emacs), 
   value is a function that executes an action plist.")

(defun register-actuator (name fn)
  "Adds a new actuator function to the system. 
   Called by I/O skills (like sk-emacs-bridge) during startup."
  (setf (gethash name *actuator-registry*) fn))

(defun inject-stimulus (raw-message)
  "The entry point for all external data. This triggers the Cognitive Loop.
   
   It implements 'Fault-Tolerant Reasoning' using Lisp restarts. If a 
   skill crashes, the daemon survives and moves to the next event."
  (let* ((payload (getf raw-message :payload))
         (async-p (getf payload :async-p)))
    (if async-p
        (bt:make-thread (lambda () 
                          (restart-case
                              (handler-bind ((error (lambda (c)
                                                      (kernel-log "ASYNC SYSTEM ERROR: ~a~%" c)
                                                      (invoke-restart 'skip-event))))
                                (cognitive-loop raw-message))
                            (skip-event () nil)))
                        :name "org-agent-async-task")
        (restart-case
            (handler-bind ((error (lambda (c)
                                    (kernel-log "SYSTEM ERROR (inject-stimulus): ~a~%" c)
                                    ;; Log the error and invoke the skip-event restart
                                    (invoke-restart 'skip-event))))
              (cognitive-loop raw-message))
          (skip-event ()
            (kernel-log "SYSTEM RECOVERY: Stimulus dropped to prevent kernel panic.~%"))))))

(defun spawn-task (task-description &key (async-p t))
  "A programmatic way for skills to delegate sub-tasks to the kernel.
   If ASYNC-P is true, it spawns a new thread, enabling 'Swarm' orchestration."
  (let ((msg `(:type :EVENT :payload (:sensor :delegation :query ,task-description :async-p ,async-p))))
    (inject-stimulus msg)))

(defun send-swarm-packet (target-url payload)
  "Serializes a cognitive context and dispatches it to a remote org-agent.
   Enables federated, cross-machine swarming."
  (let* ((json-payload (cl-json:encode-json-to-string payload))
         (headers '(("Content-Type" . "application/json"))))
    (kernel-log "SWARM - Dispatching packet to ~a..." target-url)
    (handler-case
        (dex:post target-url :headers headers :content json-payload)
      (error (c)
        (kernel-log "SWARM ERROR - Failed to reach remote instance: ~a" c)
        nil))))


(defun dispatch-action (action)
  "Routes an approved action intent to the correct physical actuator."
  (when action
    (let* ((payload (getf action :payload))
           ;; We default to :emacs for backward compatibility.
           (target (or (getf action :target) :emacs))
           (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn
          (funcall actuator-fn action)
          (kernel-log "DISPATCH ERROR: No actuator registered for target ~a~%" target)))))

;;; ============================================================================
;;; System Actuator (Self-Editing)
;;; ============================================================================

(defun execute-system-action (action)
  "Handles internal kernel operations like skill creation and hot-reloading."
  (let* ((payload (getf action :payload))
         (cmd (getf payload :action)))
    (case cmd
      (:create-skill
       (let* ((filename (getf payload :filename))
              (content (getf payload :content))
              (skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :org-agent)))
              (full-path (merge-pathnames filename skills-dir)))
         (kernel-log "ACTUATOR [System] - Creating skill ~a..." filename)
         (with-open-file (out full-path :direction :output :if-exists :supersede)
           (write-string content out))
         ;; Hot-Reload immediately
         (load-skill-from-org full-path)
         (kernel-log "ACTUATOR [System] - Skill ~a hot-reloaded." filename)))
      (:set-cascade
       (let ((new-cascade (getf payload :cascade)))
         (setf *provider-cascade* new-cascade)
         (kernel-log "ACTUATOR [System] - LLM Cascade updated to: ~a" new-cascade)))
      (:set-priority
       (let* ((name (string-downcase (format nil "~a" (getf payload :skill))))
              (val (getf payload :priority))
              (skill (gethash name *skills-registry*)))
         (if skill
             (progn
               (setf (skill-priority skill) val)
               (kernel-log "ACTUATOR [System] - Set priority of ~a to ~a" name val))
             (kernel-log "ACTUATOR [System] ERROR - Skill ~a not found" name))))
      (:auth-google-code
       (let ((code (getf payload :code)))
         (kernel-log "ACTUATOR [System] - Received Google OAuth code. Exchanging...")
         ;; We call the function in the skill package. 
         ;; Note: In a production kernel, we would use a more robust hook system.
         (if (uiop:symbol-call :org-agent.skills.org-skill-auth-google-oauth :auth-google-receive-code code)
             (kernel-log "ACTUATOR [System] - Google OAuth exchange successful.")
             (kernel-log "ACTUATOR [System] - Google OAuth exchange FAILED."))))
      (t (kernel-log "ACTUATOR [System] - Unknown command ~a" cmd)))))

;;; ============================================================================
;;; The Cognitive Loop (OODA)
;;; ============================================================================
;;; This is the pure, deterministic pipeline of the Lisp Machine. 
;;; It coordinates the transition from Perception to Action.

(defun cognitive-loop (raw-message)
  "Orchestrates the four stages of cognition with performance tracking."
  (let* ((start-time (get-internal-real-time))
         (context    (perceive raw-message))
         (skill      (find-triggered-skill context))
         (skill-name (when skill (skill-name skill))))
    
    ;; SOTA: Snapshot the memory state BEFORE thinking to enable rollback
    (snapshot-object-store)
    
    (let* ((proposed-action (think context))
           (approved-action (decide proposed-action context))
           (status (if (and proposed-action (null approved-action)) :rejected :success))
           (end-time (get-internal-real-time))
           (duration (- end-time start-time)))
      
      ;; Record telemetry for the engaged skill
      (when skill-name
        (kernel-track-telemetry skill-name duration status))
      
      (dispatch-action approved-action))))

(defun perceive (raw-message)
  "Updates the Object Store based on incoming stimulus and returns the context."
  (let ((type (getf raw-message :type))
        (payload (getf raw-message :payload)))
    (kernel-log "PERCEIVE: ~a (~a)" type (or (getf payload :sensor) "no-sensor"))
    (cond
     ((eq type :EVENT)
      (let ((sensor (getf payload :sensor)))
        (case sensor
          (:buffer-update
           (let ((ast (getf payload :ast)))
             (when ast (ingest-ast ast))))
          (:point-update
           (let ((element (getf payload :element)))
             (when element (ingest-ast element))))
          ;; Ensure we don't return NIL for these
          (:user-command t)
          (:heartbeat t)
          (:chat-message t))))
     ((eq type :RESPONSE)
      (kernel-log "ACT RESULT: ~a" (getf payload :status))))
    
    ;; ALWAYS return the raw message as the context base
    raw-message))

(defun dispatch-action (action)
  "Sends an approved action to the appropriate actuator."
  (when (and action (not (eq action :rejected)))
    (let ((target (getf action :target)))
      (kernel-log "DISPATCH: Target ~a" target)
      (let ((actuator (gethash target *actuators*)))
        (if actuator
            (funcall actuator action)
            (kernel-log "ERROR: No actuator registered for ~a" target))))))

;;; ============================================================================
;;; Daemon Lifecycle Management
;;; ============================================================================

(defun start-heartbeat ()
  "Spawns the background pulse thread. 
   Interval is controlled via HEARTBEAT_INTERVAL in .env."
  (let* ((env-interval (uiop:getenv "HEARTBEAT_INTERVAL"))
         (interval (if env-interval (parse-integer env-interval :junk-allowed t) 60)))
    (setf *heartbeat-thread*
          (bt:make-thread 
           (lambda ()
             (loop
               (sleep interval)
               (kernel-log "KERNEL: Heartbeat pulse...~%")
               (let* ((unix-time (get-universal-time))
                      ;; Inject a synthetic temporal event into the Event Bus.
                      (heartbeat-msg `(:type :EVENT :payload (:sensor :heartbeat :unix-time ,unix-time))))
                 (inject-stimulus heartbeat-msg))))
           :name "org-agent-heartbeat"))))

(defun stop-heartbeat ()
  "Gracefully terminates the pulse thread."
  (when (and *heartbeat-thread* (bt:thread-alive-p *heartbeat-thread*))
    (bt:destroy-thread *heartbeat-thread*)
    (setf *heartbeat-thread* nil)))

(defun load-all-skills ()
  "Scans the directory defined by SKILLS_DIR (defaults to notes) and hot-loads all skills.
   This is where the daemon acquires its intelligence, now unified with the Atomic Notes (Zettelkasten)."
  (let* ((env-path (uiop:getenv "SKILLS_DIR"))
         (memex-dir (uiop:getenv "MEMEX_DIR"))
         (skills-dir (cond
                       (env-path (uiop:ensure-directory-pathname env-path))
                       (memex-dir (merge-pathnames "notes/" (uiop:ensure-directory-pathname memex-dir)))
                       (t (merge-pathnames "notes/" (uiop:ensure-directory-pathname (uiop:native-namestring "~/memex/")))))))
    (if (uiop:directory-exists-p skills-dir)
        (progn
          (kernel-log "KERNEL: Loading skills from consolidated Atomic Notes (Zettelkasten): ~a" (uiop:native-namestring skills-dir))
          (let ((files (uiop:directory-files skills-dir "org-skill-*.org")))
            (if files
                (dolist (file files)
                  (load-skill-from-org file))
                (kernel-log "KERNEL: No skills found matching 'org-skill-*.org' in ~a" (uiop:native-namestring skills-dir)))))
        (kernel-log "KERNEL ERROR: Skills directory not found at ~a" (uiop:native-namestring skills-dir)))))

(defun start-daemon (&key (port 9105))
  "Boots the Neurosymbolic Kernel.
   1. Loads skills.
   2. Starts the heartbeat.
   3. Becomes ready to receive stimuli."
  (declare (ignore port))
  (register-actuator :system #'execute-system-action)
  (load-all-skills)
  (start-heartbeat)
  (kernel-log "==================================================~%")
  (kernel-log " org-agent Kernel Booted Successfully.            ~%")
  (kernel-log " Event Bus: ACTIVE                                ~%")
  (kernel-log "==================================================~%"))

(defun stop-daemon ()
  "Shutdown the kernel and all background threads."
  (stop-heartbeat)
  (kernel-log "org-agent Kernel stopped.~%"))

(defun main ()
  "The entry point for the compiled standalone binary."
  (start-daemon)
  ;; Keep the process alive.
  (loop (sleep 3600)))

