;;; org-agent-test.el --- Tests for the org-agent Emacs stub

(require 'ert)
(require 'cl-lib)
(require 'org-agent "/home/amr/.openclaw/workspace/memex/5_projects/org-agent/src/org-agent.el")

(ert-deftest test-org-agent-framing ()
  "Verify that org-agent-send correctly frames a plist."
  (let ((captured-framed nil))
    (cl-letf (((symbol-function 'process-send-string) 
               (lambda (proc string) (setq captured-framed string)))
              ((symbol-function 'process-live-p) (lambda (proc) t))
              (org-agent--process t))
      (org-agent-send '(:type :EVENT :id 1))
      (should (string= "000014(:type :EVENT :id 1)" captured-framed)))))

(ert-deftest test-org-agent-parsing ()
  "Verify that the filter correctly parses OACP framed messages."
  (let ((mock-buffer (generate-new-buffer " *org-agent-test*"))
        (received-plist nil))
    (cl-letf (((symbol-function 'org-agent--handle-message)
               (lambda (proc plist) (setq received-plist plist))))
      (with-current-buffer mock-buffer
        (insert "000014(:type :EVENT :id 1)")
        (org-agent--process-buffer mock-buffer)
        (should (equal '(:type :EVENT :id 1) received-plist))
        (should (= (buffer-size) 0))))))

(ert-deftest test-org-agent-actuator-message ()
  "Verify that the :message actuator works."
  (let ((org-agent--process nil)
        (captured-response nil))
    (cl-letf (((symbol-function 'org-agent-send)
               (lambda (plist) (setq captured-response plist))))
      (org-agent--execute-request nil 101 '(:action :message :text "Hello from Daemon"))
      ;; Check that we sent a success response back
      (should (eq :RESPONSE (plist-get captured-response :type)))
      (should (eq :success (plist-get (plist-get captured-response :payload) :status))))))

(ert-deftest test-org-agent-run-command ()
  "Verify that org-agent-run-command sends the correct event."
  (let ((captured-framed nil))
    (cl-letf (((symbol-function 'process-send-string) 
               (lambda (proc string) (setq captured-framed string)))
              ((symbol-function 'process-live-p) (lambda (proc) t))
              (org-agent--process t))
      (org-agent-run-command :test-cmd)
      (should (string-match-p ":sensor :user-command" captured-framed))
      (should (string-match-p ":command :test-cmd" captured-framed)))))

(ert-deftest test-org-agent-ast-cleaning ()
  "Verify that org-agent--clean-element produces a pure plist."
  (let* ((org-text "* Hello\nWorld")
         (ast (with-temp-buffer
                (org-mode)
                (insert org-text)
                (org-element-parse-buffer)))
         (cleaned (org-agent--clean-element ast)))
    (should (plist-get cleaned :type))
    (should (eq 'org-data (plist-get cleaned :type)))
    ;; Check that children exist
    (should (plist-get (car (plist-get cleaned :contents)) :type))
    ;; Check that we didn't leak buffer objects
    (should-not (plist-get (plist-get cleaned :properties) :buffer))))

(ert-deftest test-org-agent-actuator-eval ()
  "Verify that the :eval actuator can execute elisp."
  (let ((org-agent--process nil)
        (captured-response nil))
    (cl-letf (((symbol-function 'org-agent-send)
               (lambda (plist) (setq captured-response plist))))
      (org-agent--execute-request nil 102 '(:action :eval :code "(+ 1 2)"))
      (should (equal "3" (plist-get (plist-get captured-response :payload) :result))))))
