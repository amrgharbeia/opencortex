(in-package :org-agent)

(defun validate-harness-protocol-schema (msg)
  "Strict structural validation for incoming Harness Protocol messages."
  (unless (listp msg)
    (error "Harness Protocol Schema Error: Message must be a property list (got ~s)" (type-of msg)))
  
  (let ((type (getf msg :type)))
    (unless (member type '(:REQUEST :EVENT :RESPONSE :LOG))
      (error "Harness Protocol Schema Error: Invalid message type '~a'" type))
    
    (case type
      (:REQUEST 
       (unless (getf msg :target)
         (error "Harness Protocol Schema Error: REQUEST missing mandatory :target"))
       (unless (getf msg :payload)
         (error "Harness Protocol Schema Error: REQUEST missing mandatory :payload")))
      
      (:EVENT
       (let ((payload (getf msg :payload)))
         (unless (and payload (listp payload))
           (error "Harness Protocol Schema Error: EVENT missing or invalid :payload"))
         (unless (or (getf payload :action) (getf payload :sensor))
           (error "Harness Protocol Schema Error: EVENT payload must contain :action or :sensor"))))
      
      (:RESPONSE
       (unless (getf msg :payload)
         (error "Harness Protocol Schema Error: RESPONSE missing mandatory :payload"))))
    
    t))

(defskill :skill-harness-protocol-validator
  :priority 95
  :trigger (lambda (ctx) (member (getf (getf ctx :payload) :sensor) '(:protocol-received)))
  :neuro nil
  :symbolic (lambda (action ctx)
              (declare (ignore ctx))
              (validate-harness-protocol-schema action)
              action))
