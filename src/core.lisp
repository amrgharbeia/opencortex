(in-package :org-agent)

(defvar *system-logs* nil)
(defvar *logs-lock* (bt:make-lock "kernel-logs-lock"))
(defvar *max-log-history* 100)
(defvar *skill-telemetry* (make-hash-table :test 'equal))
(defvar *telemetry-lock* (bt:make-lock "kernel-telemetry-lock"))

(defun kernel-track-telemetry (skill-name duration status)
  (when skill-name (bt:with-lock-held (*telemetry-lock*)
                     (let ((entry (or (gethash skill-name *skill-telemetry*) (list :executions 0 :total-time 0 :failures 0))))
                       (incf (getf entry :executions)) (incf (getf entry :total-time) duration)
                       (when (eq status :rejected) (incf (getf entry :failures))) (setf (gethash skill-name *skill-telemetry*) entry)))))

(defun kernel-log (fmt &rest args)
  (let ((msg (apply #'format nil fmt args)))
    (bt:with-lock-held (*logs-lock*) (push msg *system-logs*) (when (> (length *system-logs*) *max-log-history*) (setf *system-logs* (subseq *system-logs* 0 *max-log-history*))))
    (format t "~a~%" msg) (finish-output)))

(defvar *heartbeat-thread* nil)
(defvar *actuator-registry* (make-hash-table :test 'equal))
(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive two arguments: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun inject-stimulus (raw-message &key stream)
  (let* ((payload (getf raw-message :payload)) 
         (sensor (getf payload :sensor))
         ;; Force Chat and Delegation to be async
         (async-p (or (getf payload :async-p) (member sensor '(:chat-message :delegation :user-command)))))
    (when stream (setf (getf raw-message :reply-stream) stream))
    (if async-p (bt:make-thread (lambda () (restart-case (handler-bind ((error (lambda (c) (kernel-log "ASYNC ERROR: ~a" c) (invoke-restart 'skip-event))))
                                                           (cognitive-loop raw-message)) (skip-event () nil))) :name "org-agent-async-task")
        (restart-case (handler-bind ((error (lambda (c) (kernel-log "SYSTEM ERROR: ~a" c) (invoke-restart 'skip-event)))) (cognitive-loop raw-message))
          (skip-event () (kernel-log "SYSTEM RECOVERY: Stimulus dropped.~%"))))))

(defun spawn-task (task-description &key (async-p t))
  (inject-stimulus `(:type :EVENT :payload (:sensor :delegation :query ,task-description :async-p ,async-p))))

(defun send-swarm-packet (target-url payload)
  (let* ((json-payload (cl-json:encode-json-to-string payload)) (headers '(("Content-Type" . "application/json"))))
    (handler-case (dex:post target-url :headers headers :content json-payload) (error (c) (kernel-log "SWARM ERROR: ~a" c) nil))))

(defun dispatch-action (action context)
  (when (and action (listp action))
    (let* ((target (or (ignore-errors (getf action :target)) :emacs)) (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn (funcall actuator-fn action context) (kernel-log "DISPATCH ERROR: No actuator for ~a" target)))))

(defun execute-system-action (action context)
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

(defun cognitive-loop (raw-message)
  (let* ((start-time (get-internal-real-time))
         (type (getf raw-message :type))
         (perceive-fn (find-symbol "PERCEIVE" :org-agent))
         (context (if perceive-fn (funcall perceive-fn raw-message) raw-message)))
    (snapshot-object-store)
    (if (eq type :REQUEST)
        (dispatch-action raw-message context)
        (let* ((skill (find-triggered-skill context))
               (skill-name (when skill (skill-name skill)))
               (proposed-action (think context))
               (approved-action (decide proposed-action context))
               (status (if (and proposed-action (null approved-action)) :rejected :success))
               (duration (- (get-internal-real-time) start-time)))
          (when skill-name (kernel-track-telemetry skill-name duration status))
          (dispatch-action approved-action context)))))

(defun perceive (raw-message)
  (let ((type (getf raw-message :type)) (payload (getf raw-message :payload)))
    (kernel-log "PERCEIVE: ~a (~a)" type (or (getf payload :sensor) "no-sensor"))
    (cond ((eq type :EVENT) (let ((sensor (getf payload :sensor)))
                              (case sensor
                                (:buffer-update (let ((ast (getf payload :ast))) (when ast (ingest-ast ast))))
                                (:point-update (let ((element (getf payload :element))) (when element (ingest-ast element)))))))
          ((eq type :RESPONSE) (kernel-log "ACT RESULT: ~a" (getf payload :status))))
    raw-message))

(defun start-heartbeat (&optional (interval 60))
  (setf *heartbeat-thread* (bt:make-thread (lambda () (loop (sleep interval) (kernel-log "KERNEL: Heartbeat pulse...")
                                                              (inject-stimulus `(:type :EVENT :payload (:sensor :heartbeat :unix-time ,(get-universal-time)))))) :name "org-agent-heartbeat")))

(defun stop-heartbeat () (when (and *heartbeat-thread* (bt:thread-alive-p *heartbeat-thread*)) (bt:destroy-thread *heartbeat-thread*) (setf *heartbeat-thread* nil)))

(defun load-all-skills ()
  "Scans the directory defined by SKILLS_DIR and hot-loads skills.
   Supports selective loading via SKILLS_WHITELIST environment variable."
  (let* ((env-path (uiop:getenv "SKILLS_DIR"))
         (whitelist-raw (uiop:getenv "SKILLS_WHITELIST"))
         (whitelist (when whitelist-raw (uiop:split-string whitelist-raw :separator '(#\,))))
         (skills-dir-str (or env-path (namestring (merge-pathnames "notes/" (user-homedir-pathname)))))
         (resolved-path (context-resolve-path skills-dir-str))
         (skills-dir (if resolved-path (uiop:ensure-directory-pathname resolved-path) nil)))
    (if (and skills-dir (uiop:directory-exists-p skills-dir))
        (let ((files (uiop:directory-files skills-dir "org-skill-*.org")))
          (if files
              (dolist (file files)
                (let ((skill-name (pathname-name file)))
                  (if (or (null whitelist) (member skill-name whitelist :test #'string-equal))
                      (load-skill-from-org file)
                      (kernel-log "KERNEL: Skipping skill ~a (Not in whitelist)" skill-name))))
              (kernel-log "KERNEL: No skills found in ~a" resolved-path)))
        (kernel-log "KERNEL ERROR: Skills directory not found or invalid path: ~a" skills-dir-str))))

(defvar *daemon-thread* nil) (defvar *daemon-socket* nil)
(defun handle-client (stream)
  "Main loop for a single OACP client connection."
  (kernel-log "DAEMON: New client connected.~%")
  (unwind-protect
       (loop
         (handler-case
             (progn
               ;; 1. Skip leading whitespace/newlines
               (loop for char = (peek-char nil stream nil :eof)
                     while (and (not (eq char :eof)) (member char '(#\Space #\Newline #\Return #\Tab)))
                     do (read-char stream))
               
               (let ((peek (peek-char nil stream nil :eof)))
                 (if (eq peek :eof) (return))
                 (let* ((len-prefix (make-string 6)))
                   ;; 2. Read the 6-character length prefix
                   (unless (read-sequence len-prefix stream)
                     (return))
                   (let* ((len (parse-integer len-prefix :radix 16))
                          (msg-payload (make-string len)))
                     ;; 3. Read the actual message payload
                     (unless (read-sequence msg-payload stream)
                       (return))
                     ;; 4. Parse and process
                     (let ((msg (read-from-string msg-payload)))
                       (kernel-log "DAEMON: Received stimulus (~a characters)~%" len)
                       (inject-stimulus msg :stream stream))))))
           (error (c)
             (kernel-log "DAEMON CLIENT ERROR: ~a~%" c)
             (return))))
    (kernel-log "DAEMON: Client disconnected.~%")
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
  ;; Keep the process alive.
  (loop (sleep 3600)))
