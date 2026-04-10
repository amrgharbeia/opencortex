(in-package :org-agent)

(defun router-classify-complexity (context)
  "Returns the complexity tier for a given stimulus context."
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
      
      ;; reflex: system infrastructure
      (t :REFLEX))))
