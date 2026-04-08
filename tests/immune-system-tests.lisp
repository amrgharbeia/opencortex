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
    ;; However, we can check if kernel-log received the "SYSTEM ERROR" message.
    (kernel-log "CLEAN LOG")
    (org-agent:cognitive-loop stimulus)
    (let ((logs (context-get-system-logs 10)))
      (is (cl:some (lambda (line) (search "Tool 'crashing-tool' failed: KABOOM" line)) logs)))))

(test loop-error-injection
  "Verify that a crash in think/decide triggers a :loop-error stimulus."
  (clrhash org-agent::*skills-registry*)
  (org-agent::defskill :evil-skill
    :priority 100
    :trigger (lambda (ctx) t)
    :neuro (lambda (ctx) (error "CRITICAL BRAIN FAILURE"))
    :symbolic nil)
  
  (kernel-log "CLEAN LOG")
  (org-agent:cognitive-loop '(:type :EVENT :payload (:sensor :test)))
  (let ((logs (context-get-system-logs 10)))
    ;; Check for the LOOP CRASH log from our core hook
    (is (cl:some (lambda (line) (search "LOOP CRASH - Error in recursive turn: CRITICAL BRAIN FAILURE" line)) logs))))
