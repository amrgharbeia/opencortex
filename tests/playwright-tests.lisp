(defpackage :org-agent-playwright-tests
  (:use :cl :fiveam :org-agent)
  (:export #:playwright-suite))
(in-package :org-agent-playwright-tests)

(def-suite playwright-suite :description "Tests for Playwright Browser Bridge.")
(in-suite playwright-suite)

(test test-browser-bridge-success
  "Verify that successful bridge output is parsed correctly."
  (let ((old-run-program (symbol-function 'uiop:run-program))
        (mock-output "{\"status\": \"success\", \"url\": \"https://example.com\", \"content\": \"Example Domain Content\"}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:run-program) 
                 (lambda (cmd &key input output error-output)
                   (declare (ignore cmd input output error-output))
                   mock-output))
           
           (let ((result (org-agent::execute-browser-command '((:url . "https://example.com")))))
             (is (equal "success" (cdr (assoc :status result))))
             (is (equal "Example Domain Content" (cdr (assoc :content result))))))
      (setf (symbol-function 'uiop:run-program) old-run-program))))

(test test-browser-bridge-error
  "Verify that bridge errors are captured."
  (let ((old-run-program (symbol-function 'uiop:run-program))
        (mock-output "{\"status\": \"error\", \"message\": \"Page Load Timeout\"}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'uiop:run-program) 
                 (lambda (cmd &key input output error-output)
                   (declare (ignore cmd input output error-output))
                   mock-output))
           
           (let ((result (org-agent::execute-browser-command '((:url . "https://broken.com")))))
             (is (equal "error" (cdr (assoc :status result))))
             (is (equal "Page Load Timeout" (cdr (assoc :message result))))))
      (setf (symbol-function 'uiop:run-program) old-run-program))))

(test test-browser-tool-registration
  "Verify that the :browser tool is correctly registered."
  (let ((tool (gethash "browser" org-agent::*cognitive-tools*)))
    (is (not (null tool)))
    (is (search "High-fidelity" (org-agent::cognitive-tool-description tool)))))
