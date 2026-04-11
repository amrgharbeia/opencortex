(in-package :org-agent)

(defun bouncer-process-approvals ()
  "Scans the object store for APPROVED flight plans and re-injects their actions."
  (let ((approved-nodes (list-objects-with-attribute :TODO "APPROVED"))
        (found-any nil))
    (dolist (node approved-nodes)
      (let* ((tags (getf (org-object-attributes node) :TAGS))
             (action-str (getf (org-object-attributes node) :ACTION)))
        (when (and (member "FLIGHT_PLAN" tags :test #'string-equal) action-str)
          (kernel-log "BOUNCER: Found approved flight plan ~a. Re-injecting..." (org-object-id node))
          (let ((action (ignore-errors (read-from-string action-str))))
            (when action
              ;; Add bypass flag
              (setf (getf action :approved) t)
              (inject-stimulus action)
              ;; Mark as DONE
              (setf (getf (org-object-attributes node) :TODO) "DONE")
              (setq found-any t))))))
    found-any))

(defskill :skill-bouncer
  :priority 100
  :trigger (lambda (ctx) 
             (or (eq (getf (getf ctx :payload) :sensor) :approval-required)
                 (eq (getf (getf ctx :payload) :sensor) :heartbeat)))
  :neuro nil
  :symbolic (lambda (action context)
              (declare (ignore action))
              (let* ((payload (getf context :payload))
                     (sensor (getf payload :sensor)))
                (case sensor
                  (:approval-required
                   (let* ((blocked-action (getf payload :action))
                          (id (org-id-new)))
                     (kernel-log "BOUNCER: Creating flight plan node...")
                     ;; Create the node in Emacs (or inbox)
                     (list :type :REQUEST :target :emacs :action :insert-node 
                           :id id :attributes `(:TITLE "Flight Plan: High-Risk Action" 
                                                :TODO "PLAN" 
                                                :TAGS ("FLIGHT_PLAN")
                                                :ACTION ,(format nil "~s" blocked-action)))))
                  (:heartbeat
                   ;; Periodically check for approvals
                   (bouncer-process-approvals)
                   nil)))))
