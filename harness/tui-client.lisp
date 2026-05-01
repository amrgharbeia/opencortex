(in-package :cl-user)
(defpackage :opencortex.tui
  (:use :cl :croatoan :usocket :bordeaux-threads)
  (:export :main))
(in-package :opencortex.tui)

(defvar *daemon-host* "127.0.0.1")
(defvar *daemon-port* 9105)
(defvar *socket* nil)
(defvar *stream* nil)
(defvar *chat-history* nil)
(defvar *scroll-index* 0)
(defvar *input-buffer* (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t))
(defvar *is-running* t)
(defvar *queue-lock* (bt:make-lock))
(defvar *incoming-msgs* nil)

(defun enqueue-msg (msg)
  "Thread-safe addition to incoming message queue."
  (bt:with-lock-held (*queue-lock*)
    (setf *incoming-msgs* (append *incoming-msgs* (list msg)))))

(defun dequeue-msgs ()
  "Thread-safe retrieval of incoming messages."
  (bt:with-lock-held (*queue-lock*)
    (let ((msgs *incoming-msgs*))
      (setf *incoming-msgs* nil)
      msgs)))

(defun render-chat (win h)
  (when (and win (integerp h))
    (clear win)
    (box win 0 0)
    (let* ((view-height (- h 2))
           (history (reverse *chat-history*))
           (len (length history))
           (num-to-draw (min len view-height)))
      (loop for i from 0 below num-to-draw
            for msg in history
            do (when (and msg (< (1+ i) (1- h)))
                 (add-string win (format nil "~a" msg) :y (1+ i) :x 2))))
    (refresh win)))

(defun handle-backspace ()
  (when (> (fill-pointer *input-buffer*) 0)
    (decf (fill-pointer *input-buffer*))))

(defun handle-return (stream)
  (let ((cmd (coerce *input-buffer* 'string)))
    (setf (fill-pointer *input-buffer*) 0)
    (when (> (length cmd) 0)
      (enqueue-msg (format nil "⬆ ~a" cmd))
      (handler-case
          (progn
            (when (and stream (open-stream-p stream))
              (let* ((msg (list :TYPE :EVENT 
                               :META (list :SOURCE :tui)
                               :PAYLOAD (list :SENSOR :user-input :TEXT cmd)))
                     (payload (format nil "~s" msg))
                     (len (length payload)))
                (format stream "~6,'0x~a" len payload)
                (finish-output stream)))
            (enqueue-msg "✓ Sent"))
        (error (c)
          (enqueue-msg (format nil "ERROR: Connection lost (~a)" c))
          (setf *is-running* nil))))
    (when (string= cmd "/exit") (setf *is-running* nil))
    (when (string= cmd "/clear") (setf *chat-history* nil))))

(defun start-background-reader (stream)
  (bt:make-thread
   (lambda ()
     (loop while *is-running* do
       (handler-case
           (let* ((len-buf (make-string 6))
                  (count (read-sequence len-buf stream)))
             (when (= count 6)
               (let* ((msg-len (parse-integer len-buf :radix 16))
                      (msg-buf (make-string msg-len)))
                 (read-sequence msg-buf stream)
                 (let ((msg (read-from-string msg-buf)))
                   (let ((payload (getf msg :payload)))
                     (cond
                       ((eq (getf payload :action) :handshake)
                        (enqueue-msg "* Connected to daemon *"))
                       (t
                        (let ((text (or (getf payload :text) (format nil "~a" payload))))
                          (enqueue-msg (format nil "⬇ ~a" text))))))))))
         (error (c)
           (when *is-running*
             (enqueue-msg (format nil "ERROR: Connection lost (~a)" c))
             (setf *is-running* nil))))))
   :name "opencortex-tui-reader"))

(defun main ()
  (setf (uiop:getenv "PROVIDER_CASCADE") "openrouter,openai")
  
  (handler-case
      (setf *socket* (usocket:socket-connect *daemon-host* *daemon-port*))
    (error (e) (format t "Offline: ~a~%" e) (return-from main)))
  (setf *stream* (usocket:socket-stream *socket*))
  
  (unless (uiop:getenv "TERM")
    (format t "TUI requires a terminal. Set TERM environment variable.~%")
    (return-from main))
  
  (unwind-protect
      (handler-case
          (with-screen (scr :input-echoing nil :input-blocking nil :enable-colors t)
            (let* ((h (or (height scr) 24))
                   (w (or (width scr) 80))
                   (chat-h (- h 4))
                   (input-y (- h 2)))
              (let ((chat-win (make-instance 'window :height chat-h :width (- w 2) :y 1 :x 1))
                    (input-win (make-instance 'window :height 1 :width (- w 2) :y input-y :x 1)))
                (setf (input-blocking input-win) nil)
                (start-background-reader *stream*)
                (loop :while *is-running* :do
                  (let ((msgs (dequeue-msgs)))
                    (when msgs 
                      (dolist (m msgs) (push m *chat-history*))
                      (render-chat chat-win chat-h)))
                  (let* ((ev (get-event input-win))
                         (ch (when (and ev (typep ev 'event)) (event-key ev))))
                    (when ch
                      (cond
                        ((or (eq ch #\Newline) (eq ch #\Return)) (handle-return *stream*))
                        ((or (eq ch :backspace) (eq ch (code-char 127))) (handle-backspace))
                        ((characterp ch) (vector-push-extend ch *input-buffer*))))
                    (clear input-win)
                    (add-string input-win (format nil "▶ ~a" (coerce *input-buffer* 'string)) :y 0 :x 1)
                    (refresh input-win))
                  (sleep 0.01)))))
        (error (c)
          (format t "TUI Error: ~a~%" c)))
    (setf *is-running* nil)
    (when *socket* (ignore-errors (usocket:socket-close *socket*)))))
