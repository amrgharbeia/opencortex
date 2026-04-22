(in-package :opencortex)

(defvar *interrupt-flag* nil)
(defvar *interrupt-lock* (bt:make-lock "harness-interrupt-lock"))
(defvar *heartbeat-thread* nil)

(defun process-signal (signal)
  "The entry point to the Metabolic Pipeline: Perceive -> Reason -> Act."
  (let ((current-signal signal))
    (loop while current-signal do
      (let ((depth (getf current-signal :depth 0))
            (meta (getf current-signal :meta)))
        (when (> depth 10) (harness-log "METABOLISM ERROR: Max depth reached.") (return nil))
        (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*)
          (harness-log "METABOLISM: Interrupted.")
          (bt:with-lock-held (*interrupt-lock*) (setf *interrupt-flag* nil))
          (return nil))
        (handler-case
            (progn
              (setf current-signal (perceive-gate current-signal))
              (setf current-signal (reason-gate current-signal))
              (let ((feedback (act-gate current-signal)))
                ;; feedback generation
                (if feedback
                    (progn
                      ;; Inherit meta from trigger signal
                      (unless (getf feedback :meta) (setf (getf feedback :meta) meta))
                      (setf current-signal feedback))
                    (setf current-signal nil))))
          (error (c)
            (let ((sensor (ignore-errors (getf (getf current-signal :payload) :sensor))))
              (harness-log "METABOLISM CRASH [~a]: ~a" (or sensor :unknown) c)
              ;; Only rollback on critical errors, not standard tool or loop errors
              (unless (member sensor '(:loop-error :tool-error :syntax-error))
                (harness-log "CRITICAL ERROR: Initiating Micro-Rollback.")
                (rollback-memory 0))
              (if (or (> depth 2) (member sensor '(:loop-error :tool-error)))
                  (setf current-signal nil)
                  (setf current-signal (list :type :EVENT :depth (1+ depth) :meta meta
                                             :payload (list :sensor :loop-error :message (format nil "~a" c) :depth depth)))))))))))

(defvar *auto-save-interval* 300
  "Save memory to disk every N seconds. Set from MEMORY_AUTO_SAVE_INTERVAL env.")

(defvar *heartbeat-save-counter* 0
  "Counter for auto-save triggers.")

(defun start-heartbeat ()
  "Starts the background heartbeat thread. Interval is loaded from HEARTBEAT_INTERVAL."
  (let ((interval (or (ignore-errors (parse-integer (uiop:getenv "HEARTBEAT_INTERVAL"))) 60))
        (auto-save (or (ignore-errors (parse-integer (uiop:getenv "MEMORY_AUTO_SAVE_INTERVAL"))) *auto-save-interval*)))
    (setf *auto-save-interval* auto-save)
    (setf *heartbeat-save-counter* 0)
    (setf *heartbeat-thread* 
          (bt:make-thread 
           (lambda () 
             (loop 
               (sleep interval) 
               (incf *heartbeat-save-counter*)
               (when (>= *heartbeat-save-counter* (/ *auto-save-interval* interval))
                 (setf *heartbeat-save-counter* 0)
                 (save-memory-to-disk))
               ;; inject-stimulus is synchronous for heartbeats, preventing accumulation.
               (inject-stimulus (list :type :EVENT :payload (list :sensor :heartbeat :unix-time (get-universal-time)))))) 
           :name "opencortex-heartbeat"))))

(defvar *shutdown-save-enabled* t
  "If non-nil, save memory to disk on graceful shutdown.")

(defun main ()
  "Entry point for the Skeleton MVP. Handles initialization and graceful shutdown."
  (let* ((home (uiop:getenv "HOME"))
         (env-file (uiop:merge-pathnames* ".local/share/opencortex/.env" (uiop:ensure-directory-pathname home))))
    (when (uiop:file-exists-p env-file) (cl-dotenv:load-env env-file)))

  ;; Load memory from disk if a snapshot exists
  (load-memory-from-disk)

  (initialize-actuators)
  (initialize-all-skills)

  (start-heartbeat)
  
  ;; Graceful shutdown handler for SBCL
  #+sbcl
  (sb-sys:enable-interrupt sb-unix:sigint 
                           (lambda (sig code scp) 
                             (declare (ignore sig code scp)) 
                             (harness-log "SHUTDOWN: SIGINT received. Saving memory...")
                             (when *shutdown-save-enabled* (save-memory-to-disk))
                             (uiop:quit 0)))

  (let ((sleep-interval (or (ignore-errors (parse-integer (uiop:getenv "DAEMON_SLEEP_INTERVAL"))) 3600)))
    (loop 
      (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*)
        (harness-log "SHUTDOWN: Interrupt flag set. Saving memory...")
        (when *shutdown-save-enabled* (save-memory-to-disk))
        (return))
      (sleep sleep-interval))))
