(in-package :opencortex)

(defun scribe-log-event (signal)
  "Logs a metabolic signal for later analysis."
  (let ((type (getf signal :type))
        (payload (getf signal :payload)))
    (harness-log "SCRIBE: [~a] ~s" type payload)))

(defskill :skill-scribe
  :priority 100
  :trigger (lambda (ctx) (member (getf ctx :type) '(:LOG :STATUS)))
  :deterministic (lambda (action ctx) (declare (ignore action)) (scribe-log-event ctx) nil))
