;;; opencortex-test.el --- Tests for the opencortex Emacs stub

(require 'ert)
(require 'cl-lib)
(require 'opencortex "/home/amr/.openclaw/workspace/memex/5_projects/opencortex/src/opencortex.el")

(ert-deftest test-opencortex-framing ()
  "Verify that opencortex-send correctly frames a plist."
  (let ((captured-framed nil))
    (cl-letf (((symbol-function 'process-send-string) 
               (lambda (proc string) (setq captured-framed string)))
              ((symbol-function 'process-live-p) (lambda (proc) t))
              (opencortex--process t))
      (opencortex-send '(:type :EVENT :id 1))
      (should (string= "000014(:type :EVENT :id 1)" captured-framed)))))

(ert-deftest test-opencortex-parsing ()
  "Verify that the filter correctly parses communication protocol framed messages."
  (let ((mock-buffer (generate-new-buffer " *opencortex-test*"))
        (received-plist nil))
    (cl-letf (((symbol-function 'opencortex--handle-message)
               (lambda (proc plist) (setq received-plist plist))))
      (with-current-buffer mock-buffer
        (insert "000014(:type :EVENT :id 1)")
        (opencortex--process-buffer mock-buffer)
        (should (equal '(:type :EVENT :id 1) received-plist))
        (should (= (buffer-size) 0))))))

(ert-deftest test-opencortex-actuator-message ()
  "Verify that the :message actuator works."
  (let ((opencortex--process nil)
        (captured-response nil))
    (cl-letf (((symbol-function 'opencortex-send)
               (lambda (plist) (setq captured-response plist))))
      (opencortex--execute-request nil 101 '(:action :message :text "Hello from Daemon"))
      ;; Check that we sent a success response back
      (should (eq :RESPONSE (plist-get captured-response :type)))
      (should (eq :success (plist-get (plist-get captured-response :payload) :status))))))

(ert-deftest test-opencortex-run-command ()
  "Verify that opencortex-run-command sends the correct event."
  (let ((captured-framed nil))
    (cl-letf (((symbol-function 'process-send-string) 
               (lambda (proc string) (setq captured-framed string)))
              ((symbol-function 'process-live-p) (lambda (proc) t))
              (opencortex--process t))
      (opencortex-run-command :test-cmd)
      (should (string-match-p ":sensor :user-command" captured-framed))
      (should (string-match-p ":command :test-cmd" captured-framed)))))

(ert-deftest test-opencortex-ast-cleaning ()
  "Verify that opencortex--clean-element produces a pure plist."
  (let* ((org-text "* Hello\nWorld")
         (ast (with-temp-buffer
                (org-mode)
                (insert org-text)
                (org-element-parse-buffer)))
         (cleaned (opencortex--clean-element ast)))
    (should (plist-get cleaned :type))
    (should (eq 'org-data (plist-get cleaned :type)))
    ;; Check that children exist
    (should (plist-get (car (plist-get cleaned :contents)) :type))
    ;; Check that we didn't leak buffer objects
    (should-not (plist-get (plist-get cleaned :properties) :buffer))))

(ert-deftest test-opencortex-actuator-eval ()
  "Verify that the :eval actuator can execute elisp."
  (let ((opencortex--process nil)
        (captured-response nil))
    (cl-letf (((symbol-function 'opencortex-send)
               (lambda (plist) (setq captured-response plist))))
      (opencortex--execute-request nil 102 '(:action :eval :code "(+ 1 2)"))
      (should (equal "3" (plist-get (plist-get captured-response :payload) :result))))))
