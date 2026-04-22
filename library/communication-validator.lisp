(in-package :opencortex)

(defun validate-communication-protocol-schema (msg)
  "Strict structural validation for incoming communication protocol messages."
  (unless (listp msg)
    (error "Communication Protocol Schema Error: Message must be a property list (got ~s)" (type-of msg)))
  
  (let ((type (let ((raw (proto-get msg :type))) (if (keywordp raw) (intern (string-upcase (string raw)) :keyword) raw))))
    (unless (member type '(:REQUEST :EVENT :RESPONSE :LOG :STATUS))
      (progn (harness-log "REJECTED MSG: ~s" msg) (error "Communication Protocol Schema Error: Invalid message type '~a'" type)))
    
    (case type
      (:REQUEST 
       (unless (proto-get msg :target)
         (error "Communication Protocol Schema Error: REQUEST missing mandatory :target"))
       (unless (proto-get msg :payload)
         (error "Communication Protocol Schema Error: REQUEST missing mandatory :payload")))
      
      (:EVENT
       (let ((payload (proto-get msg :payload)))
         (unless (and payload (listp payload))
           (error "Communication Protocol Schema Error: EVENT missing or invalid :payload"))
         (unless (or (proto-get payload :action) (proto-get payload :sensor))
           (error "Communication Protocol Schema Error: EVENT payload must contain :action or :sensor"))))
      
      (:RESPONSE
       (unless (proto-get msg :payload)
         (error "Communication Protocol Schema Error: RESPONSE missing mandatory :payload"))))
    
    t))

(defskill :skill-communication-protocol-validator
  :priority 95
  :trigger (lambda (ctx) (member (getf (getf ctx :payload) :sensor) '(:protocol-received)))
  :probabilistic nil
  :deterministic (lambda (action ctx)
              (declare (ignore ctx))
              (validate-communication-protocol-schema action)
              action))
