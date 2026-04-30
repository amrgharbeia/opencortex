(in-package :opencortex)

(defvar *interrupt-flag* nil
  "Atomic flag set by signal handlers to trigger graceful shutdown.")

(defvar *interrupt-lock* (bt:make-lock "harness-interrupt-lock")
  "Mutex protecting *interrupt-flag* access.")

(defvar *heartbeat-thread* nil
  "Handle to the heartbeat thread.")

(defun process-signal (signal)
  "The entry point to the Metabolic Pipeline: Perceive -> Reason -> Act."
  (let ((current-signal signal))
    (loop while current-signal do
      (let ((depth (getf current-signal :depth 0))
            (meta (getf current-signal :meta)))
        (when (> depth 10)
          (harness-log "METABOLISM ERROR: Max recursion depth reached.")
          (return nil))

        (when (bt:with-lock-held (*interrupt-lock*) *interrupt-flag*)
          (harness-log "METABOLISM: Interrupted by shutdown signal.")
          (return nil))

        (handler-case
            (progn
              (setf current-signal (perceive-gate current-signal))
              (setf current-signal (reason-gate current-signal))
              (let ((feedback (act-gate current-signal)))
                (if feedback
                    (progn
                      (unless (getf feedback :meta) (setf (getf feedback :meta) meta))
                      (setf current-signal feedback))
                    (setf current-signal nil))))
          (error (c)
            (let ((sensor (ignore-errors (getf (getf current-signal :payload) :sensor))))
              (harness-log "METABOLISM CRASH [~a]: ~a" (or sensor :unknown) c)
              (unless (member sensor '(:loop-error :tool-error :syntax-error))
                (harness-log "CRITICAL ERROR: Initiating Micro-Rollback.")
                (rollback-memory 0))
              (if (or (> depth 2) (member sensor '(:loop-error :tool-error)))
                  (setf current-signal nil)
                  (setf current-signal
                        (list :type :EVENT :depth (1+ depth) :meta meta
                              :payload (list :sensor :loop-error :message (format nil "~a" c) :depth depth)))))))))))

(defvar *auto-save-interval* 300)
(defvar *heartbeat-save-counter* 0)

(defun start-heartbeat ()
  "Starts the background heartbeat thread."
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
               (inject-stimulus
                 (list :type :EVENT :payload (list :sensor :heartbeat :unix-time (get-universal-time))))))
           :name "opencortex-heartbeat"))))

(defvar *shutdown-save-enabled* t)

(defvar *system-health* :unknown
  "Current system health status: :healthy, :degraded, :unhealthy, or :unknown.")

(defvar *health-check-ran* nil
  "Flag indicating if initial health check has completed.")

(defun run-startup-health-check ()
  "Runs the doctor diagnostics on startup. Returns health status."
  (format t "~%")
  (format t "==================================================~%")
  (format t " DOCTOR: Running Startup Health Check~%")
  (format t "==================================================~%")
  (handler-case
      (progn
        (when (fboundp 'doctor-run-all)
          (let ((result (doctor-run-all :auto-install nil)))
            (setf *health-check-ran* t)
            (if result
                (progn
                  (setf *system-health* :healthy)
                  (format t "DAEMON: Health check passed. Starting services.~%"))
                (progn
                  (setf *system-health* :degraded)
                  (format t "DAEMON: Health check found issues.~%")
                  (format t "         Run 'opencortex doctor --fix' to repair.~%")))))
        (setf *health-check-ran* t))
    (error (c)
      (format t "DOCTOR ERROR: ~a~%" c)
      (setf *system-health* :unhealthy)
      (setf *health-check-ran* t)))
  (format t "==================================================~%~%"))

(defun main ()
  "Entry point for OpenCortex. Initializes the system and enters idle loop."
  (let* ((home (uiop:getenv "HOME"))
         (env-file (uiop:merge-pathnames* ".config/opencortex/.env" (uiop:ensure-directory-pathname home))))
    (when (uiop:file-exists-p env-file)
      (cl-dotenv:load-env env-file)))

  (load-memory-from-disk)
  (initialize-actuators)
  (initialize-all-skills)
  
  ;; Run proactive doctor before starting services
  (run-startup-health-check)
  
  (start-heartbeat)
  (start-daemon)

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
