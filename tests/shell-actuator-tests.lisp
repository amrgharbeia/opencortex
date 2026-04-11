(defpackage :org-agent-shell-actuator-tests
  (:use :cl :fiveam :org-agent)
  (:export #:shell-actuator-suite))
(in-package :org-agent-shell-actuator-tests)

(def-suite shell-actuator-suite :description "Tests for Shell Actuator safety and diagnostics.")
(in-suite shell-actuator-suite)

(test test-whitelisted-execution
  "Verify that a whitelisted command executes and returns output."
  (let* ((action '(:type :REQUEST :target :tool :payload (:action :call :tool "shell" :cmd "echo \"hello shell\"")))
         (context '(:reply-stream nil))
         (original-inject (symbol-function 'org-agent:inject-stimulus))
         (captured-stimulus nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'org-agent:inject-stimulus) 
                 (lambda (stim &key stream)
                   (declare (ignore stream))
                   (setf captured-stimulus stim)))
           (org-agent::execute-shell-safely action context)
           (is (not (null captured-stimulus)))
           (is (eq :EVENT (getf captured-stimulus :type)))
           (is (eq :shell-response (getf (getf captured-stimulus :payload) :sensor)))
           (is (search "hello shell" (getf (getf captured-stimulus :payload) :stdout)))
           (is (= 0 (getf (getf captured-stimulus :payload) :exit-code))))
      (setf (symbol-function 'org-agent:inject-stimulus) original-inject))))

(test test-unlisted-command-blocked
  "Verify that a non-whitelisted command is blocked."
  (let* ((action '(:type :REQUEST :target :tool :payload (:action :call :tool "shell" :cmd "wget http://example.com")))
         (context '(:reply-stream nil))
         (original-inject (symbol-function 'org-agent:inject-stimulus))
         (captured-stimulus nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'org-agent:inject-stimulus) 
                 (lambda (stim &key stream)
                   (declare (ignore stream))
                   (setf captured-stimulus stim)))
           (org-agent::execute-shell-safely action context)
           (is (not (null captured-stimulus)))
           (is (search "ERROR - Command not in security whitelist" (getf (getf captured-stimulus :payload) :stderr)))
           (is (= 1 (getf (getf captured-stimulus :payload) :exit-code))))
      (setf (symbol-function 'org-agent:inject-stimulus) original-inject))))

(test test-command-injection-blocked
  "Verify that command injection attempts are blocked."
  (let* ((action '(:type :REQUEST :target :tool :payload (:action :call :tool "shell" :cmd "ls ; date")))
         (context '(:reply-stream nil))
         (original-inject (symbol-function 'org-agent:inject-stimulus))
         (captured-stimulus nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'org-agent:inject-stimulus) 
                 (lambda (stim &key stream)
                   (declare (ignore stream))
                   (setf captured-stimulus stim)))
           (org-agent::execute-shell-safely action context)
           (is (not (null captured-stimulus)))
           ;; With current (vulnerable) code, this might actually pass whitelisting
           ;; because the first word is "ls". We WANT this to fail.
           (is (search "ERROR" (getf (getf captured-stimulus :payload) :stderr)))
           (is (search "Security Violation" (getf (getf captured-stimulus :payload) :stderr))))
      (setf (symbol-function 'org-agent:inject-stimulus) original-inject))))

(test test-error-capture
  "Verify that a failing whitelisted command returns STDERR and exit code."
  (let* ((action '(:type :REQUEST :target :tool :payload (:action :call :tool "shell" :cmd "ls /non-existent-directory")))
         (context '(:reply-stream nil))
         (original-inject (symbol-function 'org-agent:inject-stimulus))
         (captured-stimulus nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'org-agent:inject-stimulus) 
                 (lambda (stim &key stream)
                   (declare (ignore stream))
                   (setf captured-stimulus stim)))
           (org-agent::execute-shell-safely action context)
           (is (not (null captured-stimulus)))
           (is (not (= 0 (getf (getf captured-stimulus :payload) :exit-code))))
           (is (not (equal "" (getf (getf captured-stimulus :payload) :stderr)))))
      (setf (symbol-function 'org-agent:inject-stimulus) original-inject))))
