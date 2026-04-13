(in-package :org-agent)

(defvar *async-sensors* '(:chat-message :delegation :user-command)
  "List of sensors that should be processed asynchronously to avoid blocking gateways.")

(defvar *foveal-focus-id* nil
  "The Org ID of the node the user is currently interacting with.")

(defun inject-stimulus (raw-message &key stream (depth 0))
  "Enqueues a raw message into the reactive signal pipeline."
  (let* ((payload (getf raw-message :payload)) 
         (sensor (getf payload :sensor))
         (async-p (or (getf payload :async-p) (member sensor *async-sensors*))))
    (when stream (setf (getf raw-message :reply-stream) stream))
    (if async-p 
        (bt:make-thread 
         (lambda () 
           (restart-case (handler-bind ((error (lambda (c) (harness-log "ASYNC ERROR: ~a" c) (invoke-restart 'skip-event))))
                           (process-signal raw-message)) 
             (skip-event () nil))) 
         :name "org-agent-async-task")
        (restart-case (handler-bind ((error (lambda (c) (harness-log "SYSTEM ERROR: ~a" c) (invoke-restart 'skip-event)))) 
                        (process-signal raw-message))
          (skip-event () (harness-log "SYSTEM RECOVERY: Stimulus dropped.~%"))))))

(defun perceive-gate (signal)
  "Initial processing: Normalizes raw stimuli and updates memory."
  (let* ((payload (getf signal :payload))
         (type (getf signal :type))
         (sensor (getf payload :sensor)))
    (harness-log "GATE [Perceive]: ~a (~a)" type (or sensor "no-sensor"))
    
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
                  (setf *foveal-focus-id* (ignore-errors (getf element :id)))
                  (ingest-ast element))))
             (:interrupt 
              (bt:with-lock-held (*interrupt-lock*) (setf *interrupt-flag* t)))))
          ((eq type :RESPONSE)
           (harness-log "GATE [Perceive]: Act Result -> ~a" (getf payload :status))))
           
    (setf (getf signal :status) :perceived)
    (setf (getf signal :foveal-focus) *foveal-focus-id*)
    signal))
