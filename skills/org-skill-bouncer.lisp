(in-package :opencortex)

(defvar *bouncer-network-whitelist*
  '("api.telegram.org" "matrix.org" "googleapis.com" "openai.com" "anthropic.com")
  "Domains that the Bouncer considers safe for outbound connections.")

(defun bouncer-scan-secrets (text)
  "Scans TEXT for known secrets from the vault."
  (when (and text (stringp text))
    (let ((found-secret nil))
      (maphash (lambda (key val)
                 (when (and val (stringp val) (> (length val) 5))
                   (when (search val text)
                     (setf found-secret key))))
               *vault-memory*)
      found-secret)))

(defun bouncer-check-network-exfil (cmd)
  "Detects if CMD attempts to contact an unwhitelisted external host."
  (when (and cmd (stringp cmd))
    (multiple-value-bind (match regs)
        (cl-ppcre:scan-to-strings "(http|https|ftp)://([\\w\\.-]+)" cmd)
      (declare (ignore match))
      (when regs
        (let ((domain (aref regs 1)))
          (not (some (lambda (safe) (search safe domain))
                    *bouncer-network-whitelist*)))))))

(defun bouncer-check (action context)
  "The 5-Vector security gate for high-risk actions."
  (declare (ignore context))
  (let* ((target (proto-get action :target))
         (payload (proto-get action :payload))
         (text (or (proto-get payload :text) (proto-get action :text)))
         (cmd (or (proto-get payload :cmd)
                  (when (and (eq target :tool) (equal (proto-get payload :tool) "shell"))
                    (proto-get (proto-get payload :args) :cmd))))
         (approved (proto-get action :approved)))
    (cond
      (approved action)
      ((and text (bouncer-scan-secrets text))
       (let ((secret-name (bouncer-scan-secrets text)))
         (harness-log "SECURITY VIOLATION: Blocked potential leak of secret '~a'" secret-name)
         (list :type :LOG
               :payload (list :level :error
                              :text (format nil "Action blocked: Potential exposure of '~a'" secret-name)))))
      ((and (or (eq target :shell)
                (and (eq target :tool) (equal (proto-get payload :tool) "shell")))
             (bouncer-check-network-exfil cmd))
        (harness-log "SECURITY WARNING: External network call detected. Queuing for approval.")
        (list :type :EVENT :payload (list :sensor :approval-required :action action)))
      ((or (member target '(:shell))
           (and (eq target :tool) (member (proto-get payload :tool) '("shell" "repair-file") :test #'string=))
           (and (eq target :emacs) (eq (proto-get payload :action) :eval)))
       (harness-log "SECURITY: High-impact action requires approval: ~a" (or (proto-get payload :tool) target))
       (list :type :EVENT :payload (list :sensor :approval-required :action action)))
      (t action))))

(defun bouncer-process-approvals ()
  "Scans for APPROVED flight plans and re-injects them."
  (let ((approved-nodes (list-objects-with-attribute :TODO "APPROVED"))
        (found-any nil))
    (dolist (node approved-nodes)
      (let* ((attrs (org-object-attributes node))
             (tags (getf attrs :TAGS))
             (action-str (getf attrs :ACTION)))
        (when (and (member "FLIGHT_PLAN" tags :test #'string-equal) action-str)
          (harness-log "BOUNCER: Found approved flight plan '~a'. Re-injecting..." (org-object-id node))
          (let ((action (ignore-errors (read-from-string action-str))))
            (when action
              (setf (getf action :approved) t)
              (inject-stimulus action)
              (setf (getf (org-object-attributes node) :TODO) "DONE")
              (setq found-any t)))))
    found-any))

(defun bouncer-create-flight-plan (blocked-action)
  "Creates a Flight Plan node for manual approval."
  (let ((id (org-id-new)))
    (harness-log "BOUNCER: Creating flight plan node '~a'..." id)
    (list :type :REQUEST :target :emacs
          :payload (list :action :insert-node :id id
:attributes (list :TITLE "Flight Plan: High-Risk Action"
                                          :TODO "PLAN" :TAGS '("FLIGHT_PLAN")
                                          :ACTION (format nil "~s" blocked-action))))))

(defun bouncer-deterministic-gate (action context)
  "Main deterministic gate for the Bouncer skill."
  (let* ((payload (getf context :payload))
         (sensor (getf payload :sensor)))
    (case sensor
      (:approval-required
       (bouncer-create-flight-plan (getf payload :action)))
      (:heartbeat
       (bouncer-process-approvals)
       (if action (bouncer-check action context) action))
      (otherwise
       (if action (bouncer-check action context) action)))))

(defskill :skill-bouncer
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :deterministic #'bouncer-deterministic-gate)
