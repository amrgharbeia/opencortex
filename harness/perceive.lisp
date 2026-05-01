(in-package :opencortex)

(defvar *interrupt-flag* nil)
(defvar *async-sensors* '(:chat-message :delegation :user-command)
  "Sensors that are processed in dedicated threads.")

(defvar *foveal-focus-id* nil
  "The Org ID of the node the user is currently interacting with.")

(defun inject-stimulus (raw-message &key stream (depth 0))
  "Inject a raw message into the signal processing pipeline."
  (let* ((payload (getf raw-message :payload))
         (sensor (getf payload :sensor))
         (meta (getf raw-message :meta))
         (async-p (or (getf payload :async-p)
                     (member sensor *async-sensors*))))

    (unless meta
      (setf meta (list :SOURCE :SYSTEM :SESSION-ID "internal")))

    (when stream
      (setf (getf meta :reply-stream) stream))

    (setf (getf raw-message :meta) meta)
    (setf (getf raw-message :depth) depth)

    (if async-p
        (bt:make-thread
         (lambda ()
           (restart-case (process-signal raw-message)
             (skip-event () nil)))
         :name "opencortex-async-task")
        
        (restart-case
            (handler-bind ((error (lambda (c)
                                    (harness-log "SYSTEM ERROR: ~a" c)
                                    (invoke-restart 'skip-event))))
              (process-signal raw-message))
          (skip-event ()
            (harness-log "SYSTEM RECOVERY: Stimulus dropped."))))))

(defun perceive-gate (signal)
  "Stage 1 of the metabolic pipeline: Normalize sensory input."
  (let* ((payload (getf signal :payload))
         (type (getf signal :type))
         (meta (getf signal :meta))
         (sensor (getf payload :sensor)))

    (harness-log "GATE [Perceive]: ~a (~a) [Source: ~s]"
                 type (or sensor "no-sensor") (getf meta :source))

    (cond ((eq type :EVENT)
           (case sensor
             (:buffer-update
              (let ((ast (getf payload :ast)))
                (when ast
                  (snapshot-memory)
                  (ingest-ast ast))))
             (:point-update
              (let ((element (getf payload :element)))
                (when element
                  (snapshot-memory)
                  (setf *foveal-focus-id* (getf element :id))
                  (ingest-ast element))))
             (:interrupt
              (setf *interrupt-flag* t))))
          ((eq type :RESPONSE)
           (harness-log "GATE [Perceive]: Act Result -> ~a" (getf payload :status))))

    (setf (getf signal :status) :perceived)
    (setf (getf signal :foveal-focus) *foveal-focus-id*)
    signal))
