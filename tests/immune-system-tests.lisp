(defpackage :org-agent-immune-system-tests
  (:use :cl :fiveam :org-agent)
  (:export #:immune-suite))

(in-package :org-agent-immune-system-tests)

(def-suite immune-suite
  :description "Verification of the Immune System (Core Error Hooks).")

(in-suite immune-suite)

(test tool-error-injection
  "Verify that a crashing tool triggers a :tool-error stimulus."
  (clrhash org-agent::*cognitive-tools*)
  (def-cognitive-tool :crashing-tool "Always fails."
    nil
    :body (lambda (args) (declare (ignore args)) (error "KABOOM")))
  
  (let* ((stimulus '(:type :EVENT :payload (:sensor :user-command :command :trigger-crash)))
         ;; Mock a skill that calls the crashing tool
         (skill (org-agent::make-skill 
                 :name "crasher" :priority 100 
                 :trigger-fn (lambda (ctx) t)
                 :neuro-prompt (lambda (ctx) nil)
                 :symbolic-fn (lambda (action ctx) 
                                '(:type :REQUEST :target :tool :payload (:action :call :tool "crashing-tool"))))))
    
    (clrhash org-agent::*skills-registry*)
    (setf (gethash "crasher" org-agent::*skills-registry*) skill)
    
    ;; Since cognitive-loop is recursive and our core hooks inject a NEW stimulus,
    ;; we can't easily capture it in a single synchronous call without mocking cognitive-loop.
    ;; However, we can check if harness-log received the "SYSTEM ERROR" message.
    (harness-log "CLEAN LOG")
    (org-agent:process-signal stimulus)
    (let ((logs (context-get-system-logs 20)))
      ;; We expect the pipeline to at least acknowledge the tool error
      (is (cl:some (lambda (line) (search "EVENT (TOOL-ERROR)" line)) logs)))))

(test loop-error-injection
  "Verify that a crash in think/decide triggers a :loop-error stimulus."
  (clrhash org-agent::*skills-registry*)
  (org-agent::defskill :evil-skill
    :priority 100
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :test))
    :neuro (lambda (ctx) (error "CRITICAL BRAIN FAILURE"))
    :symbolic nil)
  
  (harness-log "CLEAN LOG")
  (org-agent:process-signal '(:type :EVENT :payload (:sensor :test)))
  (let ((logs (context-get-system-logs 20)))
    ;; Check for the PIPELINE CRASH log
    (is (cl:some (lambda (line) (search "PIPELINE CRASH: CRITICAL BRAIN FAILURE" line)) logs))
    ;; Check that it was re-injected as a LOOP-ERROR
    (is (cl:some (lambda (line) (search "EVENT (LOOP-ERROR)" line)) logs))))
