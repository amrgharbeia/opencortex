(in-package :opencortex)

(defvar *policy-invariant-priorities*
  '((:transparency . 500)
    (:autonomy . 400)
    (:bloat . 300)
    (:modularity . 250)
    (:mentorship . 200)
    (:sustainability . 100))
  "Priority alist for policy invariant conflict resolution.
Higher numbers take precedence.")

(defun policy-check-transparency (action context)
  "Ensures the action is inspectable and user-facing actions carry an explanation.
Returns the action if clean, or a blocking LOG event if the action is opaque."
  (declare (ignore context))
  (unless (listp action)
    (return-from policy-check-transparency
      (list :type :LOG
            :payload (list :level :error
                           :text "POLICY [Transparency]: Action is not a valid plist. Rejected."))))
  (let* ((payload (getf action :payload))
         (target (or (getf action :target) (getf action :TARGET)))
         (explanation (or (getf payload :explanation) (getf payload :EXPLANATION)
                          (getf payload :rationale) (getf payload :RATIONALE))))
    ;; User-facing actions (CLI, TUI, Emacs) must explain themselves
    (when (and (member target '(:cli :tui :emacs :EMACS :CLI :TUI))
               (not explanation)
               (not (member (getf payload :action)
                            '(:handshake :heartbeat :status-update))))
      (return-from policy-check-transparency
        (list :type :LOG
              :payload (list :level :error
                             :text "POLICY [Transparency]: User-facing action missing :explanation. Blocked."))))
    action))

(defvar *proprietary-domain-watchlist*
  '("googleapis.com" "api.openai.com" "anthropic.com" "api.groq.com" "openrouter.ai")
  "Domains that represent centralized, proprietary control.
Actions targeting these are logged as autonomy debt, not hard-blocked,
because tactical gateway usage is permitted under the strategic mandate.")

(defun policy-scan-proprietary-references (action)
  "Scans ACTION text fields for proprietary domain references.
Returns the first matched domain, or NIL if clean."
  (let* ((payload (getf action :payload))
         (text (or (getf payload :text) (getf payload :TEXT) ""))
         (cmd (or (getf payload :cmd) (getf payload :CMD)
                  (when (equal (getf payload :tool) "shell")
                    (getf (getf payload :args) :cmd))
                  ""))
         (haystack (concatenate 'string text cmd)))
    (dolist (domain *proprietary-domain-watchlist* nil)
      (when (search domain haystack)
        (return domain)))))

(defun policy-check-autonomy (action context)
  "Flags actions that reference proprietary domains. Returns the action
with an autonomy debt log appended, or the action itself if clean."
  (declare (ignore context))
  (let ((domain (policy-scan-proprietary-references action)))
    (if domain
        (progn
          (harness-log "POLICY [Autonomy]: Detected proprietary reference '~a'. Flagged for replacement." domain)
          ;; Return a side-effect log but DO NOT block the action
          (list :type :LOG
                :payload (list :level :warn
                               :text (format nil "Autonomy Debt: Action references proprietary domain '~a'. Consider a local alternative." domain)
                               :original-action action)))
        action)))

(defvar *policy-max-skill-size-chars* 50000
  "Maximum recommended size for a skill file tangled from an Org note.")

(defun policy-check-bloat (action context)
  "Warns if a :create-skill action exceeds the bloat threshold.
Does not block, because size alone is not a proof of complexity."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (act (getf payload :action))
         (content (getf payload :content)))
    (when (and (eq act :create-skill)
               (stringp content)
               (> (length content) *policy-max-skill-size-chars*))
      (harness-log "POLICY [Bloat]: Proposed skill is ~a chars. Exceeds ~a char threshold."
                   (length content) *policy-max-skill-size-chars*)
      (return-from policy-check-bloat
        (list :type :LOG
              :payload (list :level :warn
                             :text (format nil "Bloat Warning: Proposed skill (~a chars) exceeds ~a char threshold. Review for earned complexity."
                                           (length content) *policy-max-skill-size-chars*)
                             :original-action action))))
    action))

(defvar *mentorship-required-actions*
  '(:create-skill :eval :modify-file :write-file :replace :rename-file :delete-file :shell :create-note)
  "Actions that trigger the Mentorship invariant.")

(defun policy-check-mentorship (action context)
  "Blocks high-impact actions that lack a mentorship note."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (act (or (getf payload :action) (getf action :action)))
         (note (or (getf payload :mentorship-note) (getf payload :MENTORSHIP-NOTE)))
         (target (or (getf action :target) (getf action :TARGET)))
         (tool (when (eq target :tool) (getf payload :tool))))
    (when (or (member act *mentorship-required-actions*)
              (member tool '("shell" "eval" "repair-file")))
      (unless note
        (return-from policy-check-mentorship
          (list :type :LOG
                :payload (list :level :error
                               :text "POLICY [Mentorship]: High-impact action missing :mentorship-note. Explain what you are doing and why. Blocked.")))))
    action))

(defvar *cloud-only-backends* '(:openrouter :openai :anthropic :groq :gemini-api)
  "Backends that require an internet connection and external infrastructure.")

(defun policy-check-sustainability (action context)
  "Logs sustainability debt when the action relies on cloud-only infrastructure.
Does not block, because tactical cloud usage is permitted."
  (let* ((payload (getf context :payload))
         (backend (getf payload :backend))
         (provider (getf payload :provider)))
    (when (or (member backend *cloud-only-backends*)
              (member provider *cloud-only-backends*))
      (harness-log "POLICY [Sustainability]: Cloud provider '~a' used. Logged as sustainability debt."
                   (or backend provider))
      (return-from policy-check-sustainability
        (list :type :LOG
              :payload (list :level :warn
                             :text (format nil "Sustainability Debt: Reliance on cloud provider '~a'. Consider Ollama or local inference."
                                           (or backend provider))))))
    action))

(defvar *modularity-protected-paths*
  '("harness/" "opencortex.asd")
  "Paths that constitute the unbreakable core of the system.
Any action targeting these paths must include a :modularity-justification.
This list is project-specific and should be configured at boot time.")

(defun policy-check-modularity (action context)
  "Blocks modifications to the system's protected core unless justified."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (target-file (or (getf payload :file) (getf payload :filename)))
         (justification (or (getf payload :modularity-justification)
                            (getf payload :MODULARITY-JUSTIFICATION))))
    (when (and target-file
               (some (lambda (path) (search path target-file)) *modularity-protected-paths*)
               (not justification))
      (return-from policy-check-modularity
        (list :type :LOG
              :payload (list :level :error
                             :text "POLICY [Modularity]: Modification to protected core path blocked. Provide :modularity-justification explaining why this cannot be a skill."
                             :blocked-path target-file))))
    action))

(defun policy-explain (invariant-key message &optional original-action)
  "Formats a policy decision into an auditable explanation plist.
INVARIANT-KEY is one of :transparency, :autonomy, :bloat, :modularity, :mentorship, :sustainability.
MESSAGE is a human-readable string.
ORIGINAL-ACTION is the action that was blocked or modified."
  (list :type :REQUEST
        :target (or (ignore-errors (getf (getf original-action :meta) :source)) :cli)
        :payload (list :action :message
                       :text (format nil "[POLICY ~a] ~a" invariant-key message)
                       :explanation (format nil "Invariant: ~a | Rationale: ~a" invariant-key message)
                       :original-action original-action)))

(defun policy-run-invariant-checks (action context)
  "Runs all invariant checks in priority order. Returns the final action,
a blocking LOG event, or a warning wrapper."
  (let ((checks '(policy-check-transparency
                  policy-check-autonomy
                  policy-check-bloat
                  policy-check-modularity
                  policy-check-mentorship
                  policy-check-sustainability)))
    (dolist (check-fn checks action)
      (let ((result (funcall check-fn action context)))
        ;; If the check returned a LOG event, treat it as a block/warning
        (when (and (listp result)
                   (member (getf result :type) '(:LOG :EVENT)))
           (let ((level (getf (getf result :payload) :level)))
             (cond ((eq level :error)
                    ;; Hard block: return the log event directly
                    (return-from policy-run-invariant-checks result))
                   (t
                    ;; Warning: log it, but continue with the original action
                    (harness-log "~a" (getf (getf result :payload) :text))))))))))

(defun policy-find-engineering-standards-gate ()
  "Searches for the Engineering Standards gate across known jailed package names.
Returns the function symbol, or NIL if unavailable."
  (dolist (pkg-name '(:opencortex.skills.org-skill-engineering-standards
                      :opencortex.skills.org-skill-engineering
                      :opencortex.skills.engineering-standards)
           nil)
    (let ((pkg (find-package pkg-name)))
      (when pkg
        (let ((sym (find-symbol "ENGINEERING-STANDARDS-GATE" pkg)))
          (when (and sym (fboundp sym))
            (return (symbol-function sym))))))))

(defun policy-deterministic-gate (action context)
  "The main policy gate. Runs invariant checks, then delegates to engineering standards if available.
Never returns NIL silently; always returns an action or an auditable log event."
  (let ((current-action (policy-run-invariant-checks action context)))
    ;; If an invariant returned a blocking log, do not proceed further
    (when (and (listp current-action)
               (member (getf current-action :type) '(:LOG :EVENT))
               (eq (getf (getf current-action :payload) :level) :error))
      (return-from policy-deterministic-gate current-action))
    ;; Delegate to Engineering Standards if loaded
    (let ((eng-gate (policy-find-engineering-standards-gate)))
      (when eng-gate
        (setf current-action (funcall eng-gate current-action context))))
    current-action))

(defskill :skill-policy
  :priority 500
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :probabilistic nil
  :deterministic #'policy-deterministic-gate)
