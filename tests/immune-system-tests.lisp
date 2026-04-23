(defpackage :opencortex-immune-system-tests
  (:use :cl :fiveam :opencortex)
  (:export #:immune-suite))

(in-package :opencortex-immune-system-tests)

(def-suite immune-suite
  :description "Verification of the Immune System (Core Error Hooks).")

(in-suite immune-suite)

(test tool-error-injection
  "Verify that a crashing tool triggers a :tool-error stimulus."
  (clrhash opencortex::*cognitive-tools*)
  (def-cognitive-tool :crashing-tool "Always fails."
    nil
    :body (lambda (args) (declare (ignore args)) (error "KABOOM")))
  
  (opencortex::initialize-actuators)
  (let* ((stimulus '(:type :EVENT :payload (:sensor :user-input :command :trigger-crash)))
         ;; Mock a skill that calls the crashing tool
         (skill (opencortex::make-skill 
                 :name "crasher" :priority 100 
                 :trigger-fn (lambda (ctx) t)
                 :probabilistic-prompt (lambda (ctx) nil)
                 :deterministic-fn (lambda (action ctx) 
                                '(:type :REQUEST :target :tool :payload (:action :call :tool "crashing-tool"))))))
    
    (clrhash opencortex::*skills-registry*)
    (setf (gethash "crasher" opencortex::*skills-registry*) skill)
    
    ;; Since cognitive-cycle is recursive and our core hooks inject a NEW stimulus,
    ;; we can't easily capture it in a single synchronous call without mocking cognitive-cycle.
    ;; However, we can check if harness-log received the "SYSTEM ERROR" message.
    (harness-log "CLEAN LOG")
    (opencortex:process-signal stimulus)
    (let ((logs (context-get-system-logs 20)))
      ;; We expect the pipeline to at least acknowledge the tool error
      (is (not (null (find-if (lambda (line) (search "EVENT (TOOL-ERROR)" line)) logs)))))))

(test loop-error-injection
  "Verify that a crash in think/decide triggers a :loop-error stimulus."
  (clrhash opencortex::*skills-registry*)
  (opencortex::defskill :evil-skill
    :priority 100
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :user-input))
    :probabilistic (lambda (ctx) (error "CRITICAL BRAIN FAILURE"))
    :deterministic nil)
  
  (harness-log "CLEAN LOG")
  (opencortex:process-signal '(:type :EVENT :payload (:sensor :user-input)))
  (let ((logs (context-get-system-logs 20)))
    ;; Check for the METABOLISM CRASH log
    (is (not (null (find-if (lambda (line) (search "CRITICAL BRAIN FAILURE" line)) logs))))
    ;; Check that it was re-injected as a LOOP-ERROR
    (is (not (null (find-if (lambda (line) (search "EVENT (LOOP-ERROR)" line)) logs))))))
