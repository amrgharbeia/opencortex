(in-package :org-agent)

(defun validate-harness-protocol-schema (msg)
  "Strict structural validation for incoming Harness Communication messages."
  (unless (listp msg)
    (error "Harness Communication Schema Error: Message must be a property list (got ~s)" (type-of msg)))
  
  (let ((type (getf msg :type)))
    (unless (member type '(:REQUEST :EVENT :RESPONSE :LOG))
      (error "Harness Communication Schema Error: Invalid message type '~a'" type))
    
    (case type
      (:REQUEST 
       (unless (getf msg :target)
         (error "Harness Communication Schema Error: REQUEST missing mandatory :target"))
       (unless (getf msg :payload)
         (error "Harness Communication Schema Error: REQUEST missing mandatory :payload")))
      
      (:EVENT
       (let ((payload (getf msg :payload)))
         (unless (and payload (listp payload))
           (error "Harness Communication Schema Error: EVENT missing or invalid :payload"))
         (unless (or (getf payload :action) (getf payload :sensor))
           (error "Harness Communication Schema Error: EVENT payload must contain :action or :sensor"))))
      
      (:RESPONSE
       (unless (getf msg :payload)
         (error "Harness Communication Schema Error: RESPONSE missing mandatory :payload"))))
    
    t))

(defskill :skill-harness-protocol-validator
  :priority 95
  :trigger (lambda (ctx) (member (getf (getf ctx :payload) :sensor) '(:protocol-received)))
  :probabilistic nil
  :deterministic (lambda (action ctx)
              (declare (ignore ctx))
              (validate-harness-protocol-schema action)
              action))
