(defpackage :org-agent-gateway-matrix-tests
  (:use :cl :fiveam :org-agent)
  (:export #:gateway-matrix-suite))
(in-package :org-agent-gateway-matrix-tests)

(def-suite gateway-matrix-suite :description "Tests for Matrix Gateway.")
(in-suite gateway-matrix-suite)

(test test-matrix-inbound-normalization
  "Verify that inbound Matrix sync JSON is correctly translated to a chat-message stimulus."
  (let ((old-get (symbol-function 'dex:get))
        (mock-response "{\"next_batch\":\"s123_456\",\"rooms\":{\"join\":{\"!room:hs.org\":{\"timeline\":{\"events\":[{\"type\":\"m.room.message\",\"sender\":\"@alice:hs.org\",\"content\":{\"msgtype\":\"m.text\",\"body\":\"hello matrix\"}}]}}}}}}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:get) (lambda (url &key headers connect-timeout read-timeout keep-alive) 
                                              (declare (ignore url headers connect-timeout read-timeout keep-alive))
                                              mock-response))
           (setf (uiop:getenv "MATRIX_HOMESERVER") "https://matrix.org")
           (setf (uiop:getenv "MATRIX_ACCESS_TOKEN") "test-token")
           
           (let ((captured-stimulus nil))
             (let ((original-inject (symbol-function 'org-agent:inject-stimulus)))
               (setf (symbol-function 'org-agent:inject-stimulus) 
                     (lambda (stim &key stream) (declare (ignore stream)) (setf captured-stimulus stim)))
               
               (org-agent::matrix-process-sync)
               
               (setf (symbol-function 'org-agent:inject-stimulus) original-inject)
               
               ;; Verify normalization
               (is (not (null captured-stimulus)))
               (is (eq :EVENT (getf captured-stimulus :type)))
               (is (eq :chat-message (getf (getf captured-stimulus :payload) :sensor)))
               (is (eq :matrix (getf (getf captured-stimulus :payload) :channel)))
               (is (equal "!room:hs.org" (getf (getf captured-stimulus :payload) :room-id)))
               (is (equal "@alice:hs.org" (getf (getf captured-stimulus :payload) :sender)))
               (is (equal "hello matrix" (getf (getf captured-stimulus :payload) :text)))
               (is (equal "s123_456" org-agent::*matrix-since-token*)))))
      (setf (symbol-function 'dex:get) old-get))))

(test test-matrix-outbound-formatting
  "Verify that an outbound :matrix request correctly formats the API call."
  (let ((old-put (symbol-function 'dex:put))
        (captured-url nil)
        (captured-content nil)
        (captured-headers nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:put) 
                 (lambda (url &key headers content connect-timeout read-timeout)
                   (declare (ignore connect-timeout read-timeout))
                   (setf captured-url url)
                   (setf captured-content content)
                   (setf captured-headers headers)
                   "{\"event_id\":\"$abc\"}"))
           
           (setf (uiop:getenv "MATRIX_HOMESERVER") "https://matrix.org")
           (setf (uiop:getenv "MATRIX_ACCESS_TOKEN") "test-token")
           
           (let ((action '(:type :REQUEST :target :matrix :room-id "!room:hs.org" :text "hello back")))
             (org-agent::execute-matrix-action action nil)
             
             (is (search "matrix.org/_matrix/client/v3/rooms/!room:hs.org/send/m.room.message" captured-url))
             (is (search "hello back" captured-content))
             (is (equal "Bearer test-token" (cdr (assoc "Authorization" captured-headers :test #'string=))))))
      (setf (symbol-function 'dex:put) old-put))))
