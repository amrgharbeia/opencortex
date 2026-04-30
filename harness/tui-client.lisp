(in-package :cl-user)
(defpackage :opencortex.tui
  (:use :cl :croatoan :usocket)
  (:export :main))
(in-package :opencortex.tui)

(defvar *daemon-host* "127.0.0.1")
(defvar *daemon-port* 9105)
(defvar *socket* nil)
(defvar *stream* nil)
(defvar *chat-history* nil)
(defvar *scroll-index* 0)
(defvar *input-buffer* (make-array 0 :element-type 'char :fill-pointer 0 :adjustable t))
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

(defun get-line-style (text)
  (cond
    ((uiop:string-prefix-p "*" text) '(:bold :yellow))
    ((uiop:string-prefix-p "⬆" text) '(:cyan))
    ((uiop:string-prefix-p "🤔" text) '(:italic))
    ((uiop:string-prefix-p "ERROR" text) '(:bold :red))
    (t nil)))

(defun render-chat (win)
  (clear win)
  (let* ((h (height win))
         (view-height (max 0 (- h 2)))
         (history-len (length *chat-history*))
         (start-idx *scroll-index*)
         (end-idx (min history-len (+ start-idx view-height)))
         (slice (reverse (subseq *chat-history* start-idx end-idx))))
    (loop for msg in slice
          for i from 1
          do (add-string win (format nil "│ ~a" msg) :y i :x 1 :attributes (get-line-style msg)))
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
          (format t "Send error: ~a~%" c)
          (enqueue-msg "ERROR: Connection to daemon lost.")
          (setf *is-running* nil))))
    (when (string= cmd "/exit") (setf *is-running* nil))
    (when (string= cmd "/clear") (setf *chat-history* nil))))

(defun start-background-reader (stream)
  "Starts a thread that reads framed messages from the daemon stream."
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
                       ((and (eq (getf payload :sensor) :loop-error)
                             (not (string= (or (getf payload :message) "") "Neural Cascade Failure: All providers exhausted.")))
                        (enqueue-msg (format nil "ERROR: Daemon loop error (~a)"
                                             (getf payload :message))))
                       (t
                        (let ((text (or (getf payload :text) (format nil "~a" payload))))
                          (enqueue-msg (format nil "⬇ ~a" text)))))))))
         (error (c)
           (when *is-running*
             (enqueue-msg (format nil "ERROR: Connection lost (~a)" c))
             (setf *is-running* nil))))))
   :name "opencortex-tui-reader"))

(defun main ()
  (handler-case
      (setf *socket* (usocket:socket-connect *daemon-host* *daemon-port*))
    (error (e) (format t "Offline: ~a~%" e) (return-from main)))
  (setf *stream* (usocket:socket-stream *socket*))
  
  ;; Guard: Croatoan needs a real terminal (TERM env var, real TTY)
  (unless (uiop:getenv "TERM")
    (format t "TUI requires a terminal. Set TERM environment variable.~%")
    (format t "Or use: echo 'your message' | nc localhost 9105~%")
    (return-from main))
  
  (unwind-protect
      (handler-case
          (with-screen (scr :input-echoing nil :input-blocking nil :enable-colors t)
            (let* ((h (height scr)) (w (width scr)))
              (let ((chat-win (make-instance 'window :height (- h 5) :width (- w 2) :position '(1 1) :border t))
                    (input-win (make-instance 'window :height 1 :width (- w 2) :position (list (- h 2) 1) :border t)))
                (setf (input-blocking input-win) nil)
                (start-background-reader *stream*)
                (loop :while *is-running* :do
                  (let ((msgs (dequeue-msgs)))
                    (when msgs 
                      (dolist (m msgs) (push m *chat-history*))
                      (render-chat chat-win)))
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
                  (sleep 0.02)))))
        (error (c)
          (format t "TUI Error: ~a~%" c)))
    (setf *is-running* nil)
    (when *socket* (ignore-errors (usocket:socket-close *socket*)))))
