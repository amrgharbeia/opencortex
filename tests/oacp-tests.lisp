(defpackage :org-agent-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-tests)

(def-suite oacp-suite
  :description "Test suite for org-agent Communication Protocol (OACP)")
(in-suite oacp-suite)

(test test-framing
  "Verify that messages are correctly prefixed with a 6-character hex length."
  (let ((msg "(:type :EVENT :payload (:action :handshake))"))
    ;; As the Analyst, I expect a function 'frame-message' to exist
    (is (string= "00002c(:type :EVENT :payload (:action :handshake))"
                 (org-agent:frame-message msg)))))

(test test-parse-message
  "Verify that incoming framed strings are parsed into Lisp plists."
  (let ((framed "00002c(:type :EVENT :payload (:action :handshake))"))
    (is (equal '(:type :EVENT :payload (:action :handshake))
               (org-agent:parse-message framed)))))

(test test-hello-handshake
  "Verify the structure of the HELLO handshake message."
  (let ((hello (org-agent:make-hello-message "0.1.0")))
    (is (eq :EVENT (getf hello :type)))
    (is (eq :handshake (getf (getf hello :payload) :action)))
    (is (string= "0.1.0" (getf (getf hello :payload) :version)))))

(test test-find-missing-id
  "Verify that the daemon can find a headline missing an ID."
  (let* ((ast '(:type :org-data :contents 
                ((:type :HEADLINE :properties (:TITLE "No ID Here") :contents nil)
                 (:type :HEADLINE :properties (:ID "exists" :TITLE "Has ID") :contents nil))))
         (found (org-agent::find-headline-missing-id ast)))
    (is (not (null found)))
    (is (string= "No ID Here" (getf (getf found :properties) :TITLE)))))
