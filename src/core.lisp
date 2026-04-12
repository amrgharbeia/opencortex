(in-package :org-agent)

(defvar *interrupt-flag* nil)

(defvar *interrupt-lock* (bt:make-lock "kernel-interrupt-lock"))

(defun dispatch-action (action context)
  "Routes an approved action to its registered physical actuator."
  (when (and action (listp action))
    (let* ((target (or (ignore-errors (getf action :target)) :emacs)) 
           (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn 
          (funcall actuator-fn action context) 
          (kernel-log "DISPATCH ERROR: No actuator for ~a" target)))))

(defun inject-stimulus (stimulus &key stream)
  "Entry point for all external stimuli."
  (let ((signal (list :type (getf stimulus :type)
                      :payload (getf stimulus :payload)
                      :status :inbound
                      :reply-stream stream
                      :depth 0)))
    (bt:make-thread (lambda () (process-signal signal)) :name "signal-processor")))

(defun process-signal (signal)
  "Iterative signal processing pipeline."
  (loop
    (let ((status (getf signal :status)))
      (case status
        (:inbound (setq signal (perceive-gate signal)))
        (:perceived (setq signal (neuro-gate signal)))
        (:reasoned (setq signal (consensus-gate signal)))
        (:consensus (setq signal (decide-gate signal)))
        (:decided (setq signal (dispatch-gate signal)))
        (:dispatched (return-from process-signal signal))
        (t (kernel-log "PIPELINE ERROR: Unknown status ~a" status)
           (return-from process-signal signal))))))

(defun perceive-gate (signal)
  "Stage 1: Context assembly and signal enrichment."
  (let* ((payload (getf signal :payload))
         (sensor (getf payload :sensor)))
    (kernel-log "GATE [Perceive]: ~a (~a)" (getf signal :type) (or sensor "no-sensor"))
    (setf (getf signal :context) (context-assemble-global-awareness))
    (setf (getf signal :status) :perceived)
    signal))

(defun neuro-gate (signal)
  "Stage 2: Neural reasoning (System 1)."
  (let* ((context (getf signal :context))
         (skill (find-triggered-skill signal)))
    (if skill
        (let ((neuro-fn (skill-neuro-prompt skill)))
          (if neuro-fn
              (let ((proposals (funcall neuro-fn signal)))
                (setf (getf signal :proposals) (if (and (listp proposals) (listp (first proposals))) proposals (list proposals))))
              (setf (getf signal :proposals) nil)))
        (setf (getf signal :proposals) nil))
    (setf (getf signal :status) :reasoned)
    signal))

(defun resolve-consensus (proposals signal)
  "Majority rules implementation."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (p proposals)
      (incf (gethash p counts 0)))
    (let ((winner (first proposals))
          (max-count 0))
      (maphash (lambda (p count)
                 (when (> count max-count)
                   (setq max-count count
                         winner p)))
               counts)
      (kernel-log "CONSENSUS: Winner selected with ~a votes." max-count)
      winner)))

(defun consensus-gate (signal)
  "Resolves multiple proposals into a single candidate action."
  (let ((proposals (getf signal :proposals)))
    (if (and proposals (cdr proposals))
        (let ((winner (resolve-consensus proposals signal)))
          (setf (getf signal :candidate) winner))
        (setf (getf signal :candidate) (first proposals)))
    (setf (getf signal :status) :consensus)
    signal))

(defun delegate-task (task-id recipient &key context)
  "Enqueues a task for another agent or background process."
  (kernel-log "ORCHESTRATOR: Delegating task ~a to ~a" task-id recipient)
  (inject-stimulus (list :type :EVENT 
                         :payload (list :sensor :delegation 
                                        :task-id task-id 
                                        :recipient recipient 
                                        :context context))))

(defun decide-gate (signal)
  "Stage 3: Symbolic verification (System 2)."
  (let ((candidate (getf signal :candidate)))
    (if candidate
        (let* ((normalized-candidate (if (listp candidate) candidate (list :type :RESPONSE :payload (list :text candidate))))
               (decision (decide normalized-candidate signal)))
          (setf (getf signal :approved-action) decision))
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
       (when (and approved (eq (getf approved :type) :REQUEST))
         (dispatch-action approved signal))))
    (setf (getf signal :status) :dispatched)
    signal))

(defun main ()
  "Production entry point for the org-agent daemon."
  (load-dotenv)
  (initialize-all-skills)
  (kernel-log "KERNEL: Org-agent v1.0 starting up...")
  (let ((interval (or (ignore-errors (parse-integer (uiop:getenv "HEARTBEAT_INTERVAL") :junk-allowed t)) 60)))
    (format t "KERNEL: Heartbeat interval set to ~a seconds.~%" interval)
    (start-daemon :interval interval))
  (loop (sleep 3600)))
