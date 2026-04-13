(in-package :org-agent)

(defvar *hook-registry* (make-hash-table :test 'equal)
  "Maps hook-names (symbols) to lists of functions.")

(defvar *cron-registry* (make-hash-table :test 'equal)
  "Maps task-ids to plists containing schedule and function.")

(defun orchestrator-register-hook (hook-name fn)
  "Registers a function for a named hook. Triggers a Merkle snapshot."
  (pushnew fn (gethash hook-name *hook-registry*))
  (harness-log "ORCHESTRATOR - Registered hook function for ~a" hook-name)
  (snapshot-memory)
  t)

(defun orchestrator-trigger-hook (hook-name &rest args)
  "Executes all registered functions for the given hook name."
  (let ((functions (gethash hook-name *hook-registry*)))
    (dolist (fn functions)
      (handler-case (apply fn args)
        (error (c) (harness-log "ORCHESTRATOR ERROR - Hook ~a failed: ~a" hook-name c))))))

(defun orchestrator-schedule-task (task-id schedule fn)
  "Schedules a task for execution. Schedule can be an interval (integer seconds) or 'heartbeat'."
  (setf (gethash task-id *cron-registry*) (list :schedule schedule :fn fn :last-run 0))
  (harness-log "ORCHESTRATOR - Scheduled task ~a (~a)" task-id schedule)
  (snapshot-memory)
  t)

(defun orchestrator-process-cron ()
  "Checked by the harness on every heartbeat."
  (let ((now (get-universal-time)))
    (maphash (lambda (id task)
               (let ((schedule (getf task :schedule))
                     (last-run (getf task :last-run))
                     (fn (getf task :fn)))
                 (when (or (eq schedule :heartbeat)
                           (and (integerp schedule) (>= (- now last-run) schedule)))
                   (handler-case (funcall fn)
                     (error (c) (harness-log "ORCHESTRATOR ERROR - Cron task ~a failed: ~a" id c)))
                   (setf (getf (gethash id *cron-registry*) :last-run) now))))
             *cron-registry*)))

(defun orchestrator-classify-complexity (context)
  "Returns the complexity tier (:REFLEX, :COGNITION, :REASONING) for a stimulus."
  (let* ((payload (getf context :payload))
         (sensor (getf payload :sensor))
         (skill (find-triggered-skill context))
         (skill-name (when skill (skill-name skill))))
    (cond
      ;; reasoning: generative or architectural
      ((member skill-name '("skill-architect" "skill-tech-analyst" "skill-scientist" "skill-self-fix") :test #'string-equal) :REASONING)
      ((member sensor '(:user-command)) :REASONING)
      
      ;; cognition: human interaction or semantic data
      ((member sensor '(:chat-message :delegation)) :COGNITION)
      ((member skill-name '("skill-scribe" "skill-web-research") :test #'string-equal) :COGNITION)
      
      ;; reflex: system infrastructure and background automation
      (t :REFLEX))))

(progn
  ;; Hook into kernel routing
  (setf org-agent::*model-selector-fn* #'orchestrator-classify-complexity)
  
  (defskill :skill-event-orchestrator
    :priority 400 ; Foundational control layer
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :heartbeat))
    :probabilistic nil
    :deterministic (lambda (action ctx)
                (orchestrator-process-cron)
                action)))
