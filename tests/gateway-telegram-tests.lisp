(defpackage :org-agent-gateway-telegram-tests
  (:use :cl :fiveam :org-agent)
  (:export #:gateway-telegram-suite))
(in-package :org-agent-gateway-telegram-tests)

(def-suite gateway-telegram-suite :description "Tests for Telegram Gateway.")
(in-suite gateway-telegram-suite)

(test test-telegram-inbound-normalization
  "Verify that inbound Telegram JSON is correctly translated to a chat-message stimulus."
  (let ((old-get (symbol-function 'dex:get))
        (mock-response "{\"ok\":true,\"result\":[{\"update_id\":100,\"message\":{\"message_id\":1,\"from\":{\"id\":12345,\"is_bot\":false,\"first_name\":\"Amr\"},\"chat\":{\"id\":12345,\"first_name\":\"Amr\",\"type\":\"private\"},\"date\":1678886400,\"text\":\"hello agent\"}}]}"))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:get) (lambda (url) (declare (ignore url)) mock-response))
           (setf (uiop:getenv "TELEGRAM_BOT_TOKEN") "test-token")
           
           ;; 1. Simulate the polling process
           (let ((captured-stimulus nil))
             (let ((original-inject (symbol-function 'org-agent:inject-stimulus)))
               (setf (symbol-function 'org-agent:inject-stimulus) 
                     (lambda (stim &key stream) (declare (ignore stream)) (setf captured-stimulus stim)))
               
               (org-agent::telegram-process-updates)
               
               (setf (symbol-function 'org-agent:inject-stimulus) original-inject)
               
               ;; 2. Verify normalization
               (is (not (null captured-stimulus)))
               (is (eq :EVENT (getf captured-stimulus :type)))
               (is (eq :chat-message (getf (getf captured-stimulus :payload) :sensor)))
               (is (eq :telegram (getf (getf captured-stimulus :payload) :channel)))
               (is (equal "12345" (getf (getf captured-stimulus :payload) :chat-id)))
               (is (equal "hello agent" (getf (getf captured-stimulus :payload) :text)))
               (is (= 100 org-agent::*telegram-last-update-id*)))))
      (setf (symbol-function 'dex:get) old-get))))

(test test-telegram-outbound-formatting
  "Verify that an outbound :telegram request correctly formats the API call."
  (let ((old-post (symbol-function 'dex:post))
        (captured-url nil)
        (captured-content nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'dex:post) 
                 (lambda (url &key headers content connect-timeout read-timeout)
                   (declare (ignore headers connect-timeout read-timeout))
                   (setf captured-url url)
                   (setf captured-content content)
                   "{\"ok\":true}"))
           (setf (uiop:getenv "TELEGRAM_BOT_TOKEN") "test-token")
           
           (let ((action '(:type :REQUEST :target :telegram :chat-id "12345" :text "hello human")))
             (org-agent::execute-telegram-action action nil)
             
             (is (search "api.telegram.org/bottest-token/sendMessage" captured-url))
             (is (search "12345" captured-content))
             (is (search "hello human" captured-content))))
      (setf (symbol-function 'dex:post) old-post))))
