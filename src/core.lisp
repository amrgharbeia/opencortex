(in-package :org-agent)

(defvar *system-logs* nil)
(defvar *logs-lock* (bt:make-lock "kernel-logs-lock"))
(defvar *max-log-history* 100)
(defvar *interrupt-flag* nil)
(defvar *interrupt-lock* (bt:make-lock "kernel-interrupt-lock"))
(defvar *skill-telemetry* (make-hash-table :test 'equal))
(defvar *telemetry-lock* (bt:make-lock "kernel-telemetry-lock"))

(defvar *actuator-registry* (make-hash-table :test 'equal))

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive two arguments: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun dispatch-action (action context)
  "Routes an approved action to its registered physical actuator."
  (when (and action (listp action))
    (let* ((target (or (ignore-errors (getf action :target)) :emacs)) 
           (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn 
          (funcall actuator-fn action context) 
          (kernel-log "DISPATCH ERROR: No actuator for ~a" target)))))

(defun kernel-track-telemetry (skill-name duration status)
  "Updates performance metrics for a specific skill."
  (when skill-name (bt:with-lock-held (*telemetry-lock*)
                     (let ((entry (or (gethash skill-name *skill-telemetry*) (list :executions 0 :total-time 0 :failures 0))))
                       (incf (getf entry :executions)) (incf (getf entry :total-time) duration)
                       (when (eq status :rejected) (incf (getf entry :failures))) (setf (gethash skill-name *skill-telemetry*) entry)))))

(defun kernel-log (fmt &rest args)
  "Records a formatted message to the system log and standard output."
  (let ((msg (apply #'format nil fmt args)))
    (bt:with-lock-held (*logs-lock*) (push msg *system-logs*) (when (> (length *system-logs*) *max-log-history*) (setf *system-logs* (subseq *system-logs* 0 *max-log-history*))))
    (format t "~a~%" msg) (finish-output)))

(defun inject-stimulus (raw-message &key stream (depth 0))
  "Enqueues a raw message into the reactive signal pipeline, handling async/sync execution and recovery."
  (let* ((payload (getf raw-message :payload)) 
         (sensor (getf payload :sensor))
         ;; Force Chat and Delegation to be async
         (async-p (or (getf payload :async-p) (member sensor '(:chat-message :delegation :user-command)))))
    (when stream (setf (getf raw-message :reply-stream) stream))
    (if async-p (bt:make-thread (lambda () (restart-case (handler-bind ((error (lambda (c) (kernel-log "ASYNC ERROR: ~a" c) (invoke-restart 'skip-event))))
                                                           (process-signal raw-message)) (skip-event () nil))) :name "org-agent-async-task")
        (restart-case (handler-bind ((error (lambda (c) (kernel-log "SYSTEM ERROR: ~a" c) (invoke-restart 'skip-event)))) (process-signal raw-message))
          (skip-event () (kernel-log "SYSTEM RECOVERY: Stimulus dropped.~%"))))))

(defun execute-system-action (action context)
  "Processes internal kernel commands like skill creation or environment updates."
  (declare (ignore context))
  (let* ((payload (ignore-errors (getf action :payload))) (cmd (ignore-errors (getf payload :action))))
    (case cmd
      (:eval (let ((code (getf payload :code)))
               (kernel-log "ACTUATOR [System] - Evaluating: ~a" code)
               (handler-case (let ((result (eval (read-from-string code))))
                               (kernel-log "ACTUATOR [System] - Result: ~s" result)
                               result)
                 (error (c) (kernel-log "ACTUATOR ERROR [System] - Eval failed: ~a" c)))))
      (:create-skill (let* ((filename (getf payload :filename)) (content (getf payload :content))
                            (skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :org-agent))) (full-path (merge-pathnames filename skills-dir)))
                       (kernel-log "ACTUATOR [System] - Creating skill ~a..." filename)
                       (with-open-file (out full-path :direction :output :if-exists :supersede) (write-string content out))
                       (load-skill-from-org full-path)))
      (:set-cascade (setf *provider-cascade* (getf payload :cascade)))
      (:message (kernel-log "ACTUATOR [System] - ~a" (getf payload :text)))
      (t (kernel-log "ACTUATOR [System] - Unknown command ~s" cmd)))))

(defun perceive-gate (signal)
  "Initial processing: Normalizes raw stimuli and updates memory."
  (let* ((payload (getf signal :payload))
         (type (getf signal :type))
         (sensor (getf payload :sensor)))
    (kernel-log "GATE [Perceive]: ~a (~a)" type (or sensor "no-sensor"))
    (snapshot-object-store)
    (cond ((eq type :EVENT)
           (case sensor
             (:buffer-update (let ((ast (getf payload :ast))) (when ast (ingest-ast ast))))
             (:point-update (let ((element (getf payload :element))) (when element (ingest-ast element))))
             (:interrupt (bt:with-lock-held (*interrupt-lock*) (setf *interrupt-flag* t)))))
          ((eq type :RESPONSE)
           (kernel-log "GATE [Perceive]: Act Result -> ~a" (getf payload :status))))
    (setf (getf signal :status) :perceived)
    signal))

(defun neuro-gate (signal)
  "System 1: Intuition and proposed actions."
  (unless (eq (getf signal :type) :EVENT)
    (return-from neuro-gate signal))
  (kernel-log "GATE [Neuro]: Consulting System 1...")
  (let ((thought (think signal)))
    (setf (getf signal :proposals) (if thought (list thought) nil))
    (setf (getf signal :status) :thought)
    signal))

(defun consensus-gate (signal)
  "Resolves multiple proposals into a single candidate action."
  (let ((proposals (getf signal :proposals)))
    (setf (getf signal :candidate) (first proposals))
    (setf (getf signal :status) :consensus)
    signal))

(defun decide-gate (signal)
  "System 2: Safety and validation."
  (let ((candidate (getf signal :candidate)))
    (if candidate
        (let ((approved (decide candidate signal)))
          (setf (getf signal :approved-action) approved)
          (unless approved (kernel-log "GATE [Decide]: REJECTED by System 2")))
        (setf (getf signal :approved-action) nil))
    (setf (getf signal :status) :decided)
    signal))

(defun dispatch-gate (signal)
  "Final Stage: Actuation and feedback generation."
  (let* ((approved (getf signal :approved-action))
         (type (getf signal :type))
         (depth (getf signal :depth 0))
         (feedback nil))
    (case type
      (:REQUEST (dispatch-action signal signal))
      (:EVENT 
       (when approved
         (let* ((payload (getf approved :payload))
                (target (getf approved :target))
                (action (or (getf payload :action) (getf approved :action)))
                (tool-name (or (getf payload :tool) (getf approved :tool)))
                (tool-args (or (getf payload :args) (getf approved :args))))
           (if (and (eq target :tool) (eq action :call))
               (let ((tool (gethash (string-downcase (string tool-name)) *cognitive-tools*)))
                 (if tool
                     (handler-case
                         (let* ((clean-args (if (and (listp tool-args) (listp (car tool-args))) (car tool-args) tool-args))
                                (result (funcall (cognitive-tool-body tool) clean-args)))
                           (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                                :payload (list :sensor :tool-output :result result :tool tool-name))))
                       (error (c)
                         (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                              :payload (list :sensor :tool-error :tool tool-name :message (format nil "~a" c))))))
                     (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                          :payload (list :sensor :tool-error :message "Tool not found")))))
               (let ((result (dispatch-action approved signal)))
                 (when (and result (not (member target '(:emacs :system-message))))
                   (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                        :payload (list :sensor :tool-output :result result :tool approved))))))))))
    (setf (getf signal :status) :dispatched)
    feedback))

(defun process-signal (signal)
  "The entry point to the Reactive Signal Pipeline."
  (let ((current-signal signal))
    (loop while current-signal do
      (let ((depth (getf current-signal :depth 0)))
        (when (> depth 10)
          (kernel-log "PIPELINE ERROR: Max depth reached.")
          (return nil))
        (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*)
          (kernel-log "PIPELINE: Interrupted.")
          (bt:with-lock-held (*interrupt-lock*) (setf *interrupt-flag* nil))
          (return nil))
        
        (handler-case
            (progn
              (setf current-signal (perceive-gate current-signal))
              (setf current-signal (neuro-gate current-signal))
              (setf current-signal (consensus-gate current-signal))
              (setf current-signal (decide-gate current-signal))
              (setf current-signal (dispatch-gate current-signal)))
          (error (c)
            (kernel-log "PIPELINE CRASH: ~a" c)
            (let ((sensor (ignore-errors (getf (getf current-signal :payload) :sensor))))
              (if (or (> depth 2) (member sensor '(:loop-error :tool-error)))
                  (setf current-signal nil)
                  (setf current-signal (list :type :EVENT :depth (1+ depth) :reply-stream (getf current-signal :reply-stream)
                                             :payload (list :sensor :loop-error :message (format nil "~a" c) :depth depth)))))))))))

(defvar *heartbeat-thread* nil)

(defun start-heartbeat (&optional (interval 60))
  "Spawns a thread that periodically injects a heartbeat stimulus."
  (setf *heartbeat-thread* 
        (bt:make-thread 
         (lambda () 
           (loop 
             (sleep interval) 
             (kernel-log "KERNEL: Heartbeat pulse...")
             (inject-stimulus (list :type :EVENT :payload (list :sensor :heartbeat :unix-time (get-universal-time)))))) 
         :name "org-agent-heartbeat")))

(defun stop-heartbeat () 
  "Gracefully terminates the heartbeat pulse thread."
  (when (and *heartbeat-thread* (bt:thread-alive-p *heartbeat-thread*)) 
    (bt:destroy-thread *heartbeat-thread*) 
    (setf *heartbeat-thread* nil)))

(defun load-all-skills ()
  "Scans the directory defined by SKILLS_DIR and hot-loads skills using topological order."
  (let* ((env-path (uiop:getenv "SKILLS_DIR"))
         (skills-dir-str (or env-path (namestring (merge-pathnames "notes/" (user-homedir-pathname)))))
         (resolved-path (context-resolve-path skills-dir-str))
         (skills-dir (if resolved-path (uiop:ensure-directory-pathname resolved-path) nil)))
    (if (and skills-dir (uiop:directory-exists-p skills-dir))
        (let ((sorted-files (topological-sort-skills skills-dir)))
          ;; GATEWAY ENFORCEMENT: Kernel cannot function without the Executive Soul
          (unless (member "org-skill-agent" sorted-files :key #'pathname-name :test #'string-equal)
            (error "GATEWAY FAILURE: org-skill-agent.org not found in skills directory."))
          (dolist (file sorted-files)
            (kernel-log "KERNEL: Loading skill ~a..." (pathname-name file))
            (load-skill-with-timeout file 5)))
        (kernel-log "KERNEL ERROR: Skills directory not found: ~a" skills-dir-str))))

(defvar *daemon-thread* nil) (defvar *daemon-socket* nil)
(defvar *emacs-clients* nil)
(defvar *clients-lock* (bt:make-lock "emacs-clients-lock"))

(defun register-emacs-client (stream)
  "Tracks an active Emacs socket connection."
  (bt:with-lock-held (*clients-lock*)
    (pushnew stream *emacs-clients*)))

(defun unregister-emacs-client (stream)
  "Removes a disconnected Emacs socket from the registry."
  (bt:with-lock-held (*clients-lock*)
    (setf *emacs-clients* (remove stream *emacs-clients*))))

(defun handle-client (stream)
  "Main loop for a single OACP client connection."
  (kernel-log "DAEMON: New client connected.~%")
  (register-emacs-client stream)
  (unwind-protect
       (loop
         (handler-case
             (progn
               (loop for char = (peek-char nil stream nil :eof)
                     while (and (not (eq char :eof)) (member char '(#\Space #\Newline #\Return #\Tab)))
                     do (read-char stream))
               (let ((peek (peek-char nil stream nil :eof)))
                 (if (eq peek :eof) (return))
                 (let* ((len-prefix (make-string 6)))
                   (unless (read-sequence len-prefix stream) (return))
                   (let* ((len (parse-integer len-prefix :radix 16))
                          (msg-payload (make-string len)))
                     (unless (read-sequence msg-payload stream) (return))
                     (let ((msg (read-from-string msg-payload)))
                       (kernel-log "DAEMON: Received stimulus (~a characters)~%" len)
                       (inject-stimulus msg :stream stream))))))
           (error (c) (kernel-log "DAEMON CLIENT ERROR: ~a~%" c) (return))))
    (kernel-log "DAEMON: Client disconnected.~%")
    (unregister-emacs-client stream)
    (ignore-errors (close stream))))

(defun start-daemon (&key port interval)
  (let* ((env-host (uiop:getenv "DAEMON_HOST")) (env-port (uiop:getenv "ORG_AGENT_DAEMON_PORT"))
         (listen-host (if env-host (string-trim " \"'" env-host) "127.0.0.1"))
         (listen-port (or (or port (when env-port (ignore-errors (parse-integer (string-trim " \"'" env-port) :junk-allowed t)))) 9105)))
    (register-actuator :system #'execute-system-action) 
    (register-actuator :emacs (lambda (action context) 
                                (declare (ignore context))
                                (kernel-log "ACTUATOR [Emacs] - Action: ~a~%" action)))
    (start-heartbeat (or interval 60))
    (kernel-log "DAEMON: Binding to ~a:~a..." listen-host listen-port)
    (setf *daemon-socket* (usocket:socket-listen listen-host listen-port :reuse-address t))
    (setf *daemon-thread* (bt:make-thread (lambda () (unwind-protect (loop (handler-case (let ((client-socket (usocket:socket-accept *daemon-socket*)))
                                                                                          (bt:make-thread (lambda () (handle-client (usocket:socket-stream client-socket))) :name "org-agent-client-handler"))
                                                                                      (error (c) (kernel-log "DAEMON ERROR: ~a" c) (sleep 0.1))))
                                                       (usocket:socket-close *daemon-socket*))) :name "org-agent-tcp-listener"))
    (kernel-log "==================================================~% org-agent Kernel Booted Successfully.~% Daemon Listening: ~a:~a~%==================================================" listen-host listen-port)
    (load-all-skills)))

(defun stop-daemon () (stop-heartbeat) (when *daemon-socket* (usocket:socket-close *daemon-socket*) (setf *daemon-socket* nil)) (kernel-log "org-agent Kernel stopped.~%"))

(defun main ()
  "The entry point for the compiled standalone binary."
  (let* ((home (uiop:getenv "HOME"))
         (env-file (uiop:merge-pathnames* ".local/share/org-agent/.env" (uiop:ensure-directory-pathname home))))
    (if (uiop:file-exists-p env-file)
        (progn
          (format t "KERNEL: Loading environment from ~a~%" env-file)
          (cl-dotenv:load-env env-file))
        (format t "KERNEL ERROR: .env not found at ~a~%" env-file)))
  (let ((interval (or (ignore-errors (parse-integer (uiop:getenv "HEARTBEAT_INTERVAL") :junk-allowed t)) 60)))
    (format t "KERNEL: Heartbeat interval set to ~a seconds.~%" interval)
    (start-daemon :interval interval))
  (loop (sleep 3600)))
