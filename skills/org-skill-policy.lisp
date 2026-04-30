(in-package :opencortex)

(defun policy-check (action context)
  "Enforces constitutional invariants on proposed actions."
  (declare (ignore context))
  (let* ((payload (proto-get action :payload))
         (explanation (proto-get payload :explanation)))
    (if (and explanation (stringp explanation) (> (length explanation) 10))
        action
        (progn
          (harness-log "POLICY VIOLATION: Action lacks sufficient explanation.")
          (list :type :LOG
                :payload (list :level :warn
                              :text "Action blocked: Missing or insufficient :explanation. Please justify your reasoning."))))))

(defskill :skill-policy
  :priority 500
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :deterministic #'policy-check)
