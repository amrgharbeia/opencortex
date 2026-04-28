(in-package :opencortex)

(defvar *policy-invariant-priorities*
  '((:transparency . 500)
    (:autonomy . 400)
    (:bloat . 300)
    (:modularity . 250)
    (:mentorship . 200)
    (:sustainability . 100))
  "Priority alist for policy invariant conflict resolution.
Higher numbers take precedence.

When two invariants conflict, the higher priority wins.
Example: Modularity (250) takes precedence over Mentorship (200),
meaning a change that would fatten the harness is blocked
even if it would be educational.")

(defvar *proprietary-domain-watchlist*
  '("googleapis.com" "api.openai.com" "anthropic.com" "api.groq.com" "openrouter.ai")
  "Domains representing centralized, proprietary control.

  Actions targeting these are logged as autonomy debt, not hard-blocked.
  This is because tactical gateway usage (Telegram, Signal, OpenRouter)
  is permitted under the strategic mandate for autonomy.

  Strategic goal: Replace all proprietary APIs with local alternatives.
  Tactical reality: Use what's available while building toward that goal.")

(defvar *policy-max-skill-size-chars* 50000
  "Maximum recommended size for a skill file tangled from an Org note.

  This is a soft limit—the check warns but does not block.
  A large, well-documented skill is acceptable; a small, poorly-documented
  one that adds unnecessary complexity is not.")

(defvar *modularity-protected-paths*
  '("harness/" "opencortex.asd")
  "Paths that constitute the unbreakable core of the system.

  Any action targeting these paths must include a :modularity-justification
  explaining why the change cannot be implemented as a skill.

  The Thin Harness principle: What belongs in the harness?
  - Core signal processing (Perceive-Reason-Act loop)
  - Memory and persistence primitives
  - Protocol definition and validation
  - Skills register and dispatch

  What belongs in skills?
  - Policy and security
  - LLM integration
  - Domain-specific functionality
  - New actuators")

(defvar *mentorship-required-actions*
  '(:create-skill :eval :modify-file :write-file :replace
    :rename-file :delete-file :shell :create-note)
  "Actions that trigger the Mentorship invariant.

  These are high-impact actions that should come with explanations
  not just for the user, but for future debugging and maintenance.")

(defvar *cloud-only-backends* '(:openrouter :openai :anthropic :groq :gemini-api)
  "Backends requiring internet connection and external infrastructure.

  These are acceptable as fallbacks when local inference is unavailable,
  but should be logged as sustainability debt for tracking purposes.")



(defun policy-check-transparency (action context)
(defun policy-check-transparency (action context)
  "Ensures the action is inspectable and user-facing actions carry an explanation.

  TRANSPARENCY CHECK:
  1. Action must be a valid plist (not opaque data)
  2. User-facing actions (:cli, :tui, :emacs) must include :explanation
  3. Heartbeat and handshake messages are exempt (they're system status)

  Returns the action if clean, or a blocking LOG event if violated."

  (declare (ignore context))

  ;; Check 1: Action must be a valid plist
  (unless (listp action)
    (return-from policy-check-transparency
      (list :type :LOG
            :payload (list :level :error
                           :text "POLICY [Transparency]: Action is not a valid plist. Rejected."))))

  (let* ((payload (getf action :payload))
         (target (or (getf action :target) (getf action :TARGET)))
         (explanation (or (getf payload :explanation)
                          (getf payload :EXPLANATION)
                          (getf payload :rationale)
                          (getf payload :RATIONALE))))

    ;; Check 2: User-facing actions require explanation
    (when (and (member target '(:cli :tui :emacs :EMACS :CLI :TUI))
               (not explanation)
               (not (member (getf payload :action)
                            '(:handshake :heartbeat :status-update))))
      (return-from policy-check-transparency
        (list :type :LOG
              :payload (list :level :error
                             :text "POLICY [Transparency]: User-facing action missing :explanation. Blocked."))))

    action))

(defun policy-scan-proprietary-references (action)
  "Scans ACTION text fields for proprietary domain references.

  Searches in:
  - :text and :TEXT in payload
  - :cmd and :CMD in payload
  - :cmd in args (for shell tool calls)

  Returns the first matched domain, or NIL if clean."

  (let* ((payload (getf action :payload))
         (text (or (getf payload :text) (getf payload :TEXT) ""))
         (cmd (or (getf payload :cmd)
                 (getf payload :CMD)
                 (when (equal (getf payload :tool) "shell")
                   (getf (getf payload :args) :cmd))
                 ""))
         (haystack (concatenate 'string text cmd)))

    (dolist (domain *proprietary-domain-watchlist* nil)
      (when (search domain haystack)
        (return domain)))))

(defun policy-check-autonomy (action context)
  "Flags actions that reference proprietary domains.

  Does NOT block the action—this is a warning, not a veto.
  The agent can use proprietary services tactically, but must
  be aware that each usage is a step away from full autonomy.

  Returns a warning LOG if proprietary reference detected,
  or the original action if clean."

  (declare (ignore context))

  (let ((domain (policy-scan-proprietary-references action)))

    (if domain
        (progn
          (harness-log "POLICY [Autonomy]: Detected proprietary reference '~a'. Flagged for replacement." domain)
          ;; Return a warning log but DO NOT block the action
          (list :type :LOG
                :payload (list :level :warn
                               :text (format nil "Autonomy Debt: Action references proprietary domain '~a'. Consider a local alternative." domain)
                               :original-action action)))

        action)))

(defun policy-check-bloat (action context)
  "Warns if a :create-skill action exceeds the bloat threshold.

  Size alone is not proof of complexity—a 50KB skill that's well-designed
  is better than a 5KB skill that's spaghetti. This check flags for review,
  not automatic rejection.

  Returns a warning LOG if threshold exceeded, or original action if clean."

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

(defun policy-check-modularity (action context)
  "Blocks modifications to the system's protected core unless justified.

  MODULARITY CHECK:
  1. If the action targets a protected path
  2. And no :modularity-justification is provided
  3. Then block with an explanation

  The justification should explain WHY the change cannot be a skill.
  Common valid reasons:
  - The change fixes a bug in the harness itself
  - The change adds a primitive that skills cannot implement
  - The change is required for security hardening

  Invalid reasons:
  - 'It's easier to modify the harness'
  - 'Skills are too slow'
  - 'I want to keep it all in one place'"

  (declare (ignore context))

  (let* ((payload (getf action :payload))
         (target-file (or (getf payload :file)
                         (getf payload :filename)))
         (justification (or (getf payload :modularity-justification)
                            (getf payload :MODULARITY-JUSTIFICATION))))

    (when (and target-file
               (some (lambda (path) (search path target-file))
                    *modularity-protected-paths*)
               (not justification))

      (return-from policy-check-modularity
        (list :type :LOG
              :payload (list :level :error
                             :text "POLICY [Modularity]: Modification to protected core path blocked. Provide :modularity-justification explaining why this cannot be a skill."
                             :blocked-path target-file))))

  action))

(defun policy-check-mentorship (action context)
  "Blocks high-impact actions that lack a mentorship note.

  MENTORSHIP CHECK:
  1. If the action is in *mentorship-required-actions*
  2. Or if the action calls shell/eval/repair-file tools
  3. Then require :mentorship-note explaining what and why

  The mentorship note should be:
  - Concise (1-2 sentences)
  - Educational (explain the principle, not just the action)
  - Actionable (help the user understand the outcome)"

  (declare (ignore context))

  (let* ((payload (getf action :payload))
         (act (or (getf payload :action)
                 (getf action :action)))
         (note (or (getf payload :mentorship-note)
                  (getf payload :MENTORSHIP-NOTE)))
         (target (or (getf action :target)
                    (getf action :TARGET)))
         (tool (when (eq target :tool)
                (getf payload :tool))))

    (when (or (member act *mentorship-required-actions*)
              (member tool '("shell" "eval" "repair-file")))

      (unless note
        (return-from policy-check-mentorship
          (list :type :LOG
                :payload (list :level :error
                               :text "POLICY [Mentorship]: High-impact action missing :mentorship-note. Explain what you are doing and why. Blocked.")))))

  action))

(defun policy-check-sustainability (action context)
  "Logs sustainability debt when action relies on cloud-only infrastructure.

  Does NOT block—this is informational, not prohibitive.
  Cloud usage is acceptable tactically (when local models fail),
  but every cloud usage should be a conscious decision, not a default."

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

  action)))

(defun policy-explain (invariant-key message &optional original-action)
  "Formats a policy decision into an auditable explanation plist.

  INVARIANT-KEY is one of:
    :transparency, :autonomy, :bloat, :modularity, :mentorship, :sustainability

  MESSAGE is a human-readable string explaining the decision.

  ORIGINAL-ACTION is the action that was blocked or modified.

  Returns a REQUEST plist addressed to the original source,
  containing the explanation and original action for transparency."

  (list :type :REQUEST
        :target (or (ignore-errors
                    (getf (getf original-action :meta) :source))
                   :cli)
        :payload (list :action :message
                       :text (format nil "[POLICY ~a] ~a" invariant-key message)
                       :explanation (format nil "Invariant: ~a | Rationale: ~a"
                                            invariant-key message)
                       :original-action original-action)))

(defun policy-run-invariant-checks (action context)
  "Runs all invariant checks in priority order.

  Priority order (from *policy-invariant-priorities*):
  1. Transparency (500) - blocks non-transparent actions
  2. Autonomy (400) - warns on proprietary dependencies
  3. Bloat (300) - warns on oversized skills
  4. Modularity (250) - blocks unprotected core modifications
  5. Mentorship (200) - blocks unexplained high-impact actions
  6. Sustainability (100) - warns on cloud dependencies

  Returns:
  - The final action (possibly modified by checks)
  - A blocking LOG event (if any check returned :error level)
  - A warning wrapper (if checks returned :warn level but no blocks)"

  (let ((checks '(policy-check-transparency
                  policy-check-autonomy
                  policy-check-bloat
                  policy-check-modularity
                  policy-check-mentorship
                  policy-check-sustainability)))

    (dolist (check-fn checks action)
      (let ((result (funcall check-fn action context)))

        ;; If the check returned a LOG/EVENT, interpret it
        (when (and (listp result)
                   (member (getf result :type) '(:LOG :EVENT)))

          (let ((level (getf (getf result :payload) :level)))

            (cond
              ;; Hard block: error level stops processing immediately
              ((eq level :error)
               (return-from policy-run-invariant-checks result))

              ;; Soft warning: log but continue with original action
              (t
               (harness-log "~a" (getf (getf result :payload) :text))))))))))
(defun policy-find-engineering-standards-gate ()
  "Searches for the Engineering Standards gate across known jailed package names.

  The standards skill may be in opencortex-contrib submodule,
  so we search multiple possible package names with graceful fallback.

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
  "The main policy gate entry point.

  This function is registered as the deterministic-fn for the policy skill.
  It runs invariant checks, then delegates to engineering standards if loaded.

  IMPORTANT: Never returns NIL silently. Always returns either:
  - An action (possibly modified)
  - A blocking LOG event with explanation
  - A warning wrapper with explanation"

  ;; Step 1: Run invariant checks
  (let ((current-action (policy-run-invariant-checks action context)))

    ;; Step 2: If an invariant blocked the action, stop here
    (when (and (listp current-action)
               (member (getf current-action :type) '(:LOG :EVENT))
               (eq (getf (getf current-action :payload) :level) :error))

      (return-from policy-deterministic-gate current-action))

    ;; Step 3: Delegate to Engineering Standards if loaded
    (let ((eng-gate (policy-find-engineering-standards-gate)))
      (when eng-gate
        (setf current-action (funcall eng-gate current-action context))))

    current-action))

(defskill :skill-policy
  :priority 500
  :trigger (lambda (ctx) (declare (ignore ctx)) t)
  :probabilistic nil
  :deterministic #'policy-deterministic-gate)
