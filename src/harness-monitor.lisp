(in-package :org-agent)

(org-agent:def-cognitive-tool :harness-status \"Returns the current operational status of the Org-Agent harness, including loaded skills and telemetry.\"
  nil
  :body (lambda (args)
          (declare (ignore args))
          (format nil \"HARNESS STATUS:
- Active Skills: ~a
- Uptime: ~a seconds
- Memory Usage: ~a
- Providers: ~a\"
                  (hash-table-count org-agent:*skills-registry*)
                  (get-universal-time)
                  \"Not implemented\"
                  org-agent:*provider-cascade*)))

(org-agent:def-cognitive-tool :list-skills \"Lists all currently loaded skills and their metadata.\"
  nil
  :body (lambda (args)
          (declare (ignore args))
          (let ((output \"LOADED SKILLS:
\"))
            (maphash (lambda (name skill)
                       (setf output (concatenate 'string output
                                                 (format nil \"- ~a (Priority: ~a, Deps: ~s)~%\"
                                                         name
                                                         (org-agent:skill-priority skill)
                                                         (org-agent:skill-dependencies skill)))))
                     org-agent:*skills-registry*)
            output)))

(defskill :skill-harness-monitor
  :priority 100
  :trigger (lambda (context) t)
  :neuro (lambda (context) \"You are the Harness Monitor. Use your tools to provide system visibility.\")
  :symbolic (lambda (action context) action))
