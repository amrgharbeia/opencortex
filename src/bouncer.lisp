(in-package :org-agent)
(defun bouncer-scan-secrets (text)
  "Returns the name of the secret found in TEXT, or NIL if clean."
  (when (and text (stringp text))
    (let ((found-secret nil))
      (maphash (lambda (key val)
                 (when (and val (stringp val) (> (length val) 5))
                   (when (search val text)
                     (setf found-secret key))))
               *vault-memory*)
      found-secret)))

(in-package :org-agent)
(defun bouncer-check-network-exfil (cmd)
  "Returns T if the command appears to target an unwhitelisted external host."
  (when (and cmd (stringp cmd))
    ;; Basic check for common data exfiltration tools being used with IPs/URLs
    (let ((network-whitelist '("api.telegram.org" "matrix.org" "googleapis.com" "openai.com" "anthropic.com")))
      (when (cl-ppcre:scan "(http|https|ftp)://([\\w\\.-]+)" cmd)
        (multiple-value-bind (match regs) 
            (cl-ppcre:scan-to-strings "(http|https|ftp)://([\\w\\.-]+)" cmd)
          (declare (ignore match))
          (let ((domain (aref regs 1)))
            (not (some (lambda (safe) (search safe domain)) network-whitelist))))))))

(in-package :org-agent)
(defun bouncer-check (action context)
  "The 5-Vector security gate. Blocks or queues actions based on risk."
  (let* ((target (getf action :target))
         (payload (getf action :payload))
         (text (or (getf payload :text) (getf action :text)))
         ;; Extract cmd from direct shell or tool-mediated shell call
         (cmd (or (getf payload :cmd)
                  (when (and (eq target :tool) (equal (getf payload :tool) "shell"))
                    (getf (getf payload :args) :cmd))))
         (approved (getf action :approved)))
    
    (cond
      ;; 0. Bypass for already approved actions
      (approved action)

      ;; 1. Secret Exposure Vector (Hard Block)
      ((and text (bouncer-scan-secrets text))
       (let ((secret-name (bouncer-scan-secrets text)))
         (harness-log "SECURITY VIOLATION: Blocked leak of secret ~a" secret-name)
         `(:type :log :payload (:level :error :text ,(format nil "Action blocked: Potential exposure of ~a" secret-name)))))

      ;; 2. Network Exfiltration Vector (Authorization Required)
      ((and (or (eq target :shell) 
                (and (eq target :tool) (equal (getf payload :tool) "shell")))
            (bouncer-check-network-exfil cmd))
       (harness-log "SECURITY WARNING: External network call detected. Queuing for approval.")
       `(:type :EVENT :payload (:sensor :approval-required :action ,action)))

      ;; 3. High-Impact Target Vector (Authorization Required)
      ((or (member target '(:shell))
           (and (eq target :tool) (member (getf payload :tool) '("shell" "repair-file") :test #'string=))
           (and (eq target :emacs) (eq (getf payload :action) :eval)))
       (harness-log "SECURITY: High-impact action ~a requires approval." (or (getf payload :tool) target))
       `(:type :EVENT :payload (:sensor :approval-required :action ,action)))

      ;; 4. Default Pass
      (t action))))

(in-package :org-agent)
(defun bouncer-process-approvals ()
  "Scans the object store for APPROVED flight plans and re-injects their actions."
  (let ((approved-nodes (list-objects-with-attribute :TODO "APPROVED"))
        (found-any nil))
    (dolist (node approved-nodes)
      (let* ((tags (getf (org-object-attributes node) :TAGS))
             (action-str (getf (org-object-attributes node) :ACTION)))
        (when (and (member "FLIGHT_PLAN" tags :test #'string-equal) action-str)
          (harness-log "BOUNCER: Found approved flight plan ~a. Re-injecting..." (org-object-id node))
          (let ((action (ignore-errors (read-from-string action-str))))
            (when action
              ;; Mark as approved to bypass the gate
              (setf (getf action :approved) t)
              (inject-stimulus action)
              ;; Mark as DONE
              (setf (getf (org-object-attributes node) :TODO) "DONE")
              (setq found-any t))))))
    found-any))

(in-package :org-agent)
(defskill :skill-bouncer
  :priority 100
  :trigger (lambda (ctx) 
             (or (eq (getf (getf ctx :payload) :sensor) :approval-required)
                 (eq (getf (getf ctx :payload) :sensor) :heartbeat)))
  :probabilistic nil
  :deterministic (lambda (action context)
              (declare (ignore action))
              (let* ((payload (getf context :payload))
                     (sensor (getf payload :sensor)))
                (case sensor
                  (:approval-required
                   (let* ((blocked-action (getf payload :action))
                          (id (org-id-new)))
                     (harness-log "BOUNCER: Creating flight plan node...")
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
