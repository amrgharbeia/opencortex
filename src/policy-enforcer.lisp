(in-package :org-agent)

(defskill :skill-policy-enforcer
  :priority 1000 ; Absolute highest priority
  :trigger (lambda (context) t) ; Always active as a fallback
  :probabilistic (lambda (context)
           \"You are the Org-Agent Policy Enforcer. Your goal is to ensure all actions empower the user through the Lisp Machine and adhere to the System Policy.\")
  :deterministic (lambda (action context)
              ;; Basic invariant check: Block actions that appear to violate sovereignty
              (let ((payload (getf action :payload)))
                (if (and payload (search \"proprietary\" (format nil \"~s\" payload)))
                    (progn
                      (org-agent:harness-log \"DETERMINISTIC [Policy]: Sovereignty violation suspected. Blocking action.\")
                      nil)
                    action))))
