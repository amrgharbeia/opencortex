(defpackage :org-agent-gateway-signal-tests
  (:use :cl :fiveam :org-agent)
  (:export #:gateway-signal-suite))
(in-package :org-agent-gateway-signal-tests)

(def-suite gateway-signal-suite :description "Tests for Signal Gateway.")
(in-suite gateway-signal-suite)

(test test-signal-inbound-normalization
  "Verify that inbound Signal-cli JSON is correctly translated to a chat-message stimulus."
  (let ((old-run-program (symbol-function 'uiop:run-program))
        (mock-json "{\"envelope\":{\"source\":\"+14107054317\",\"sourceDevice\":1,\"timestamp\":1678886400000,\"dataMessage\":{\"timestamp\":1678886400000,\"message\":\"hello signal\",\"expiresInSeconds\":0,\"attachments\":[]}}}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:run-program) 
                 (lambda (cmd &key output error-output ignore-error-status)
                   (declare (ignore output error-output ignore-error-status))
                   (if (member "receive" cmd :test #'string=)
                       mock-json
                       "")))
           
           (let ((captured-stimulus nil))
             (let ((original-inject (symbol-function 'org-agent:inject-stimulus)))
               (setf (symbol-function 'org-agent:inject-stimulus) 
                     (lambda (stim &key stream) (declare (ignore stream)) (setf captured-stimulus stim)))
               
               (org-agent::signal-process-updates)
               
               (setf (symbol-function 'org-agent:inject-stimulus) original-inject)
               
               ;; Verify normalization
               (is (not (null captured-stimulus)))
               (is (eq :EVENT (getf captured-stimulus :type)))
               (is (eq :chat-message (getf (getf captured-stimulus :payload) :sensor)))
               (is (eq :signal (getf (getf captured-stimulus :payload) :channel)))
               (is (equal "+14107054317" (getf (getf captured-stimulus :payload) :chat-id)))
               (is (equal "hello signal" (getf (getf captured-stimulus :payload) :text))))))
      (setf (symbol-function 'uiop:run-program) old-run-program))))

(test test-signal-outbound-formatting
  "Verify that an outbound :signal request correctly formats the CLI call."
  (let ((old-run-program (symbol-function 'uiop:run-program))
        (captured-cmd nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:run-program) 
                 (lambda (cmd &key output error-output ignore-error-status)
                   (declare (ignore output error-output ignore-error-status))
                   (setf captured-cmd cmd)
                   ""))
           
           (let ((action '(:type :REQUEST :target :signal :chat-id "+14107054317" :text "hello from lisp")))
             (org-agent::execute-signal-action action nil)
             
             (is (member "signal-cli" captured-cmd :test #'string=))
             (is (member "send" captured-cmd :test #'string=))
             (is (member "+14107054317" captured-cmd :test #'string=))
             (is (member "hello from lisp" captured-cmd :test #'string=))))
      (setf (symbol-function 'uiop:run-program) old-run-program))))
