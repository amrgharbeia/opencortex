(in-package :org-agent)

(defvar *interrupt-flag* nil)
(defvar *interrupt-lock* (bt:make-lock "harness-interrupt-lock"))

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
            (harness-log "METABOLISM CRASH: ~a - Initiating Micro-Rollback." c)
            (rollback-object-store 0)
            (let ((sensor (ignore-errors (getf (getf current-signal :payload) :sensor))))
              (if (or (> depth 2) (member sensor '(:loop-error :tool-error)))
                  (setf current-signal nil)
                  (setf current-signal (list :type :EVENT :depth (1+ depth) :reply-stream (getf current-signal :reply-stream)
                                             :payload (list :sensor :loop-error :message (format nil "~a" c) :depth depth)))))))))))

(defvar *default-heartbeat-interval* 60)
(defvar *heartbeat-thread* nil)

(defun start-heartbeat (&optional (interval *default-heartbeat-interval*))
  (setf *heartbeat-thread* 
        (bt:make-thread 
         (lambda () 
           (loop 
             (sleep interval) 
             (inject-stimulus (list :type :EVENT :payload (list :sensor :heartbeat :unix-time (get-universal-time)))))) 
         :name "org-agent-heartbeat")))

(defun main ()
  "Entry point for the Skeleton MVP."
  (let* ((home (uiop:getenv "HOME"))
         (env-file (uiop:merge-pathnames* ".local/share/org-agent/.env" (uiop:ensure-directory-pathname home))))
    (when (uiop:file-exists-p env-file) (cl-dotenv:load-env env-file)))
  (initialize-all-skills)
  (start-heartbeat)
  (loop (sleep 3600)))
