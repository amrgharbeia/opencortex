(in-package :opencortex)

(defvar *interrupt-flag* nil)
(defvar *interrupt-lock* (bt:make-lock "harness-interrupt-lock"))
(defvar *heartbeat-thread* nil)

(defun process-signal (signal)
  "The entry point to the Metabolic Pipeline: Perceive -> Reason -> Act."
  (let ((current-signal signal))
    (loop while current-signal do
      (let ((depth (getf current-signal :depth 0)))
        (when (> depth 10) (harness-log "METABOLISM ERROR: Max depth reached.") (return nil))
        (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*)
          (harness-log "METABOLISM: Interrupted.")
          (bt:with-lock-held (*interrupt-lock*) (setf *interrupt-flag* nil))
          (return nil))
        (handler-case
            (progn
              (setf current-signal (perceive-gate current-signal))
              (setf current-signal (reason-gate current-signal))
              (setf current-signal (act-gate current-signal)))
          (error (c)
            (let ((sensor (ignore-errors (getf (getf current-signal :payload) :sensor))))
              (harness-log "METABOLISM CRASH [~a]: ~a" (or sensor :unknown) c)
              ;; Only rollback on critical errors, not standard tool or loop errors
              (unless (member sensor '(:loop-error :tool-error :syntax-error))
                (harness-log "CRITICAL ERROR: Initiating Micro-Rollback.")
                (rollback-memory 0))
              (if (or (> depth 2) (member sensor '(:loop-error :tool-error)))
                  (setf current-signal nil)
                  (setf current-signal (list :type :EVENT :depth (1+ depth) :reply-stream (getf current-signal :reply-stream)
                                             :payload (list :sensor :loop-error :message (format nil "~a" c) :depth depth)))))))))))

(defun start-heartbeat ()
  "Starts the background heartbeat thread. Interval is loaded from HEARTBEAT_INTERVAL."
  (let ((interval (or (ignore-errors (parse-integer (uiop:getenv "HEARTBEAT_INTERVAL"))) 60)))
    (setf *heartbeat-thread* 
          (bt:make-thread 
           (lambda () 
             (loop 
               (sleep interval) 
               ;; inject-stimulus is synchronous for heartbeats, preventing accumulation.
               (inject-stimulus (list :type :EVENT :payload (list :sensor :heartbeat :unix-time (get-universal-time)))))) 
           :name "opencortex-heartbeat"))))

(defun main ()
  "Entry point for the Skeleton MVP. Handles initialization and graceful shutdown."
  (let* ((home (uiop:getenv "HOME"))
         (env-file (uiop:merge-pathnames* ".local/share/opencortex/.env" (uiop:ensure-directory-pathname home))))
    (when (uiop:file-exists-p env-file) (cl-dotenv:load-env env-file)))
  
  (initialize-actuators)
  (initialize-all-skills)

  (start-heartbeat)
  
  ;; Graceful shutdown handler for SBCL
  #+sbcl
  (sb-sys:enable-interrupt sb-unix:sigint 
                           (lambda (sig code scp) 
                             (declare (ignore sig code scp)) 
                             (harness-log "SHUTDOWN: SIGINT received. Exiting...")
                             (uiop:quit 0)))

  (let ((sleep-interval (or (ignore-errors (parse-integer (uiop:getenv "DAEMON_SLEEP_INTERVAL"))) 3600)))
    (loop 
      (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*) (return))
      (sleep sleep-interval))))
