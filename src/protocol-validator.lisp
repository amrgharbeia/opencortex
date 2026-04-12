(in-package :org-agent)

(defun validate-oacp-schema (msg)
  "Strict structural validation for incoming OACP messages."
  (unless (listp msg)
    (error "OACP Schema Error: Message must be a property list (got ~s)" (type-of msg)))
  
  (let ((type (getf msg :type)))
    (unless (member type '(:REQUEST :EVENT :RESPONSE :LOG))
      (error "OACP Schema Error: Invalid message type '~a'" type))
    
    (case type
      (:REQUEST 
       (unless (getf msg :target)
         (error "OACP Schema Error: REQUEST missing mandatory :target"))
       (unless (getf msg :payload)
         (error "OACP Schema Error: REQUEST missing mandatory :payload")))
      
      (:EVENT
       (let ((payload (getf msg :payload)))
         (unless (and payload (listp payload))
           (error "OACP Schema Error: EVENT missing or invalid :payload"))
         (unless (or (getf payload :action) (getf payload :sensor))
           (error "OACP Schema Error: EVENT payload must contain :action or :sensor"))))
      
      (:RESPONSE
       (unless (getf msg :payload)
         (error "OACP Schema Error: RESPONSE missing mandatory :payload"))))
    
    t))

(defskill :skill-oacp-validator
  :priority 95
  :trigger (lambda (ctx) (member (getf (getf ctx :payload) :sensor) '(:protocol-received)))
  :neuro nil
  :symbolic (lambda (action ctx)
              (declare (ignore ctx))
              (validate-oacp-schema action)
              action))
