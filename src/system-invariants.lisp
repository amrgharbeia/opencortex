(in-package :org-agent)

(org-agent:def-cognitive-tool :harness-status "Returns the current operational status of the Org-Agent harness, including loaded skills and telemetry."
  nil
  :body (lambda (args)
          (declare (ignore args))
          (format nil "HARNESS STATUS:
- Active Skills: ~a
- Uptime: ~a seconds
- Memory Usage: ~a
- Providers: ~a"
                  (hash-table-count org-agent:*skills-registry*)
                  (get-universal-time) ; Placeholder for actual uptime
                  "Not implemented"
                  org-agent:*provider-cascade*)))

(org-agent:def-cognitive-tool :list-skills "Lists all currently loaded skills and their metadata."
  nil
  :body (lambda (args)
          (declare (ignore args))
          (let ((output "LOADED SKILLS:
"))
            (maphash (lambda (name skill)
                       (setf output (concatenate 'string output
                                                 (format nil "- ~a (Priority: ~a, Deps: ~s)~%"
                                                         name
                                                         (org-agent:skill-priority skill)
                                                         (org-agent:skill-dependencies skill)))))
                     org-agent:*skills-registry*)
            output)))

(org-agent:defskill :skill-system-invariants
  :priority 1000 ; Absolute highest priority
  :trigger (lambda (context) t) ; Always active as a fallback
  :neuro (lambda (context)
           "You are the Org-Agent System Invariants Skill. Your goal is to empower the user through the Lisp Machine.
Follow the Core Invariants:
1. Sovereignty: Avoid proprietary traps.
2. Technical Mastery: Explain your logic.
3. Zero-Bloat: Keep it minimal.
4. Transparency: Your thoughts are auditable.
5. Sustainability: Think long-term.")
  :symbolic (lambda (action context)
              ;; Basic invariant check: Block actions that appear to violate sovereignty
              (let ((payload (getf action :payload)))
                (if (and payload (search "proprietary" (format nil "~s" payload)))
                    (progn
                      (org-agent:harness-log "DELIBERATE [Invariants]: Sovereignty violation suspected. Blocking action.")
                      nil)
                    action))))
