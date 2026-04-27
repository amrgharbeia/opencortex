(in-package :opencortex)

(defvar *async-sensors* '(:chat-message :delegation :user-command)
  "Sensors that are processed in dedicated threads.

  These sensors can block (waiting for API responses, user input, etc.)
  so they run in separate threads to avoid blocking the main pipeline.

  Other sensors (:heartbeat, :interrupt, :buffer-update) are processed
  synchronously to maintain temporal ordering.")

(defvar *foveal-focus-id* nil
  "The Org ID of the node the user is currently interacting with.

  This enables the reasoning engine to provide contextually relevant
  responses. When editing a specific note, the agent knows which
  note you're referring to without needing explicit ID references.

  Updated on :point-update events from Emacs.")

(defun inject-stimulus (raw-message &key stream (depth 0))
  "Inject a raw message into the signal processing pipeline.

  RAW-MESSAGE is a property list that will be normalized into a Signal.
  STREAM is an optional output stream for responses (used by TUI/CLI).
  DEPTH tracks recursion depth for feedback loops.

  This function determines whether to process synchronously or
  asynchronously based on the sensor type, then calls process-signal
  to run through the Perceive -> Reason -> Act pipeline.

  Error handling: Uses restarts to prevent individual signals from
  crashing the entire system. Failed signals are logged and dropped."

  (let* ((payload (getf raw-message :payload))
         (sensor (getf payload :sensor))
         (meta (getf raw-message :meta))
         (async-p (or (getf payload :async-p)
                     (member sensor *async-sensors*))))

    ;; Ensure metadata exists
    (unless meta
      (setf meta (list :SOURCE :SYSTEM :SESSION-ID "internal")))

    ;; Attach reply stream if provided
    (when stream
      (setf (getf meta :reply-stream) stream))

    (setf (getf raw-message :meta) meta)

    (if async-p
        ;; Async: process in dedicated thread
        (bt:make-thread
         (lambda ()
           (restart-case
               (handler-bind ((error (lambda (c)
                                       (harness-log "ASYNC ERROR: ~a" c)
                                       (invoke-restart 'skip-event))))
                 (process-signal raw-message))
             (skip-event () nil)))
         :name "opencortex-async-task")

        ;; Sync: process in main thread with recovery
        (restart-case
            (handler-bind ((error (lambda (c)
                                    (harness-log "SYSTEM ERROR: ~a" c)
                                    (invoke-restart 'skip-event))))
              (process-signal raw-message))
          (skip-event ()
            (harness-log "SYSTEM RECOVERY: Stimulus dropped."))))))

(defun perceive-gate (signal)
  "Stage 1 of the metabolic pipeline: Normalize sensory input.

  This function:
  1. Logs the incoming signal for debugging
  2. Handles special sensor types (:buffer-update, :point-update, etc.)
  3. Updates the Memory graph with incoming data
  4. Tracks foveal focus (user's current node)
  5. Sets :status to :perceived

  Modifies the signal in place and returns it for the next stage.

  Memory snapshots are taken before AST updates to enable rollback
  if the update causes issues."

  (let* ((payload (getf signal :payload))
         (type (getf signal :type))
         (meta (getf signal :meta))
         (sensor (getf payload :sensor)))

    ;; Log the incoming signal for debugging
    (harness-log "GATE [Perceive]: ~a (~a) [Source: ~s]"
                 type (or sensor "no-sensor") (getf meta :source))

    ;; Handle EVENT type sensors
    (cond ((eq type :EVENT)
           (case sensor

             ;; Org buffer was modified - update memory
             (:buffer-update
              (let ((ast (getf payload :ast)))
                (when ast
                  (snapshot-memory)  ; Enable rollback if update causes issues
                  (ingest-ast ast))))

             ;; Point moved to different org node - update focus
             (:point-update
              (let ((element (getf payload :element)))
                (when element
                  (snapshot-memory)
                  ;; Track foveal focus for contextual reasoning
                  (setf *foveal-focus-id*
                        (ignore-errors (getf element :id)))
                  (ingest-ast element))))

             ;; System interrupt - trigger shutdown
             (:interrupt
              (bt:with-lock-held (*interrupt-lock*)
                (setf *interrupt-flag* t)))))

          ;; Log responses from actuators
          ((eq type :RESPONSE)
           (harness-log "GATE [Perceive]: Act Result -> ~a"
                       (getf payload :status))))

    ;; Update signal status
    (setf (getf signal :status) :perceived)
    (setf (getf signal :foveal-focus) *foveal-focus-id*)
    signal))
