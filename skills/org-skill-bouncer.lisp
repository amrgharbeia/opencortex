(in-package :opencortex)

(defun bouncer-scan-secrets (text)
  "Scans TEXT for known secrets from the vault.

  RETURNS: The name of the matched secret, or NIL if text is clean.

  This prevents the catastrophic failure mode where the agent
  accidentally echoes an API key in its response or log output.

  The check uses substring matching (not regex) for reliability.
  Only secrets longer than 5 characters are checked to avoid
  false positives on common words."

  (when (and text (stringp text))

    (let ((found-secret nil))

      (maphash (lambda (key val)
                 ;; Only check secrets of meaningful length
                 (when (and val (stringp val) (> (length val) 5))
                   ;; Search for secret value in action text
                   (when (search val text)
                     (setf found-secret key))))

               opencortex::*vault-memory*)

      found-secret)))

(defvar *bouncer-network-whitelist*
  '("api.telegram.org" "matrix.org" "googleapis.com" "openai.com" "anthropic.com")
  "Domains that the Bouncer considers safe for outbound connections.

  This whitelist should be minimal—only services explicitly configured
  as gateways. All other outbound connections require approval.")

(defun bouncer-check-network-exfil (cmd)
  "Detects if CMD attempts to contact an unwhitelisted external host.

  Returns T if the command targets an unknown external host.
  Returns NIL if the command is clean or only contacts whitelisted hosts.

  The check looks for HTTP/HTTPS/FTP URLs and extracts the domain.
  If the domain isn't in *bouncer-network-whitelist*, it's flagged."

  (when (and cmd (stringp cmd))

    ;; Look for URL patterns in the command
    (when (cl-ppcre:scan "(http|https|ftp)://([\\w\\.-]+)" cmd)

      (multiple-value-bind (match regs)
          (cl-ppcre:scan-to-strings "(http|https|ftp)://([\\w\\.-]+)" cmd)

        (declare (ignore match))

        (let ((domain (aref regs 1)))

          ;; Check if domain is whitelisted
          (not (some (lambda (safe) (search safe domain))
                    *bouncer-network-whitelist*)))))))

(defun bouncer-check (action context)
  "The 5-Vector security gate for high-risk actions.

  Evaluates an action against all security vectors and either:
  - Returns the action unchanged (pass)
  - Returns a blocking LOG event (hard block)
  - Returns an approval-required EVENT (soft block)

  Vector evaluation order:
  1. Already approved actions pass immediately
  2. Secret exposure → hard block
  3. Network exfiltration → approval required
  4. High-impact targets → approval required

  The context parameter is not used directly but provided for
  consistency with the skill gate signature."

  (declare (ignore context))

  (let* ((target (getf action :target))
         (payload (getf action :payload))
         (text (or (getf payload :text) (getf action :text)))
         ;; Extract cmd from direct shell or tool-mediated shell call
         (cmd (or (getf payload :cmd)
                 (when (and (eq target :tool)
                           (equal (getf payload :tool) "shell"))
                   (getf (getf payload :args) :cmd))))
         (approved (getf action :approved)))

    (cond

      ;; Vector 0: Already approved actions pass through
      (approved
       action)

      ;; Vector 1: Secret Exposure (Hard Block)
      ;; If any vault secret is found in the action text, block immediately
      ((and text (bouncer-scan-secrets text))
       (let ((secret-name (bouncer-scan-secrets text)))
         (harness-log "SECURITY VIOLATION: Blocked potential leak of secret '~a'" secret-name)
         (list :type :LOG
               :payload (list :level :error
                              :text (format nil "Action blocked: Potential exposure of '~a'" secret-name)))))

      ;; Vector 2: Network Exfiltration (Soft Block)
      ;; Shell commands targeting unknown hosts require approval
      ((and (or (eq target :shell)
               (and (eq target :tool)
                   (equal (getf payload :tool) "shell")))
            (bouncer-check-network-exfil cmd))

       (harness-log "SECURITY WARNING: External network call detected. Queuing for approval.")

       (list :type :EVENT
             :payload (list :sensor :approval-required
                           :action action)))

      ;; Vector 3: High-Impact Targets (Soft Block)
      ;; Shell execution, file repair, and eval require approval
      ((or (member target '(:shell))
          (and (eq target :tool)
              (member (getf payload :tool) '("shell" "repair-file") :test #'string=))
          (and (eq target :emacs)
              (eq (getf payload :action) :eval)))

       (harness-log "SECURITY: High-impact action requires approval: ~a"
                   (or (getf payload :tool) target))

       (list :type :EVENT
             :payload (list :sensor :approval-required
                           :action action)))

      ;; Vector 4: Default pass
      (t
       action))))

(defun bouncer-process-approvals ()
  "Scans the object store for APPROVED flight plans and re-injects them.

  This function is called on every heartbeat, allowing the agent to
  check for approvals without blocking the main signal pipeline.

  Flight Plan format:
  - Has TAGS including \"FLIGHT_PLAN\"
  - Has TODO set to \"APPROVED\"
  - Has ACTION containing the serialized action plist

  When an approved flight plan is found:
  1. Deserialize the action from the ACTION attribute
  2. Mark the action as :approved = t (bypasses security gate)
  3. Re-inject into the signal pipeline
  4. Mark the flight plan as DONE

  Returns T if any flight plans were processed."

  (let ((approved-nodes (list-objects-with-attribute :TODO "APPROVED"))
        (found-any nil))

    (dolist (node approved-nodes)

      (let* ((tags (getf (org-object-attributes node) :TAGS))
             (action-str (getf (org-object-attributes node) :ACTION)))

        ;; Only process flight plans (not other APPROVED items)
        (when (and (member "FLIGHT_PLAN" tags :test #'string-equal)
                  action-str)

          (harness-log "BOUNCER: Found approved flight plan '~a'. Re-injecting..."
                      (org-object-id node))

          (let ((action (ignore-errors (read-from-string action-str))))
            (when action

              ;; Mark as approved to bypass the security gate on re-injection
              (setf (getf action :approved) t)

              ;; Re-inject the action into the signal pipeline
              (inject-stimulus action)

              ;; Mark the flight plan as done
              (setf (getf (org-object-attributes node) :TODO) "DONE")

              (setq found-any t))))))

    found-any))

(defun bouncer-create-flight-plan (blocked-action)
  "Creates an Org node representing a pending flight plan for manual approval.

  BLOCKED-ACTION is the action plist that was intercepted.

  The flight plan node contains:
  - A title describing the action
  - TODO set to PLAN (awaiting approval)
  - TAGS including FLIGHT_PLAN
  - ACTION attribute containing the serialized action

  The user reviews the flight plan and changes TODO to APPROVED.
  On the next heartbeat, bouncer-process-approvals will detect
  the approval and re-inject the action.

  Returns the generated org-id for the flight plan."

    (let ((id (org-id-new)))
      (harness-log "BOUNCER: Creating flight plan node '~a'..." id)

      ;; Inject a node creation request
      (list :type :REQUEST
            :target :emacs
            :payload (list :action :insert-node
                          :id id
                          :attributes (list
                                       :TITLE "Flight Plan: High-Risk Action"
                                       :TODO "PLAN"
                                       :TAGS '("FLIGHT_PLAN")
                                       :ACTION (format nil "~s" blocked-action))))))

(defun bouncer-deterministic-gate (action context)
  "Main deterministic gate for the Bouncer skill.

  Handles three types of signals:
  1. :approval-required - Create a flight plan for the blocked action
  2. :heartbeat - Process any pending approvals
  3. otherwise - Run security check on the action

  The trigger is always true (bouncer evaluates all actions)
  because security cannot be selective."

  (let* ((payload (getf context :payload))
         (sensor (getf payload :sensor)))

    (case sensor

      ;; Signal type 1: Action was blocked, create flight plan
      (:approval-required
       (let* ((blocked-action (getf payload :action)))
         (bouncer-create-flight-plan blocked-action)))

      ;; Signal type 2: Heartbeat, check for approvals
      (:heartbeat
       (bouncer-process-approvals)
       ;; After processing approvals, still run the security check
       (if action
           (bouncer-check action context)
           action))

      ;; Signal type 3: Normal action, run security check
      (otherwise
       (if action
           (bouncer-check action context)
           action)))))

(defskill :skill-bouncer
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :probabilistic nil
  :deterministic #'bouncer-deterministic-gate)
