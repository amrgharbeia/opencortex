(defpackage :opencortex-tests
  (:use :cl :fiveam :opencortex))
(in-package :opencortex-tests)

(def-suite communication-protocol-suite
  :description "Test suite for opencortex Communication Protocol (communication protocol)")
(in-suite communication-protocol-suite)

(test test-framing
  "Verify that messages are correctly prefixed with a 6-character hex length."
  (let* ((msg '(:type :EVENT :payload (:action :handshake)))
         (framed (opencortex:frame-message msg))
         (len-str (subseq framed 0 6))
         (payload (subseq framed 6)))
    (is (string= "00002C" (string-upcase len-str)))
    (is (equalp msg (read-from-string payload)))))

(test test-parse-message
  "Verify that incoming framed strings are parsed into Lisp plists."
  (let ((framed "00002c(:type :EVENT :payload (:action :handshake))"))
    (is (equal '(:type :EVENT :payload (:action :handshake))
               (opencortex:parse-message framed)))))

(test test-hello-handshake
  "Verify the structure of the HELLO handshake message."
  (let ((hello (opencortex:make-hello-message "0.1.0")))
    (is (eq :EVENT (getf hello :type)))
    (is (eq :handshake (getf (getf hello :payload) :action)))
    (is (string= "0.1.0" (getf (getf hello :payload) :version)))))

(test test-find-missing-id
  "Verify that the daemon can find a headline missing an ID."
  (let* ((ast '(:type :org-data :contents 
                ((:type :HEADLINE :properties (:TITLE "No ID Here") :contents nil)
                 (:type :HEADLINE :properties (:ID "exists" :TITLE "Has ID") :contents nil))))
         (found (opencortex::find-headline-missing-id ast)))
    (is (not (null found)))
    (is (string= "No ID Here" (getf (getf found :properties) :TITLE)))))
