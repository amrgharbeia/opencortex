(in-package :cl-user)

(defpackage :opencortex.tui
  (:use :cl :croatoan)
  (:export :main))

(in-package :opencortex.tui)

(defvar *daemon-host* "127.0.0.1")

(defvar *daemon-port* 9105)

(defvar *socket* nil)

(defvar *stream* nil)

(defvar *chat-history* (list) "Full chronological log of messages.")

(defvar *scroll-index* 0 "Offset for history rendering.")

(defvar *status-text* "Connecting...")

(defvar *input-buffer* (make-array 0 :element-type 'char :fill-pointer 0 :adjustable t))

(defvar *command-history* (make-array 0 :element-type 't :fill-pointer 0 :adjustable t))

(defvar *history-index* -1)

(defvar *is-running* t)

(defvar *queue-lock* (bt:make-lock))

(defvar *incoming-msgs* nil)

(defun enqueue-msg (msg)
  "Thread-safe addition to incoming message queue."
  (bt:with-lock-held (*queue-lock*)
    (push msg *incoming-msgs*)))

(defun dequeue-msgs ()
  "Thread-safe retrieval of incoming messages."
  (bt:with-lock-held (*queue-lock*)
    (let ((msgs (nreverse *incoming-msgs*)))
      (setf *incoming-msgs* nil)
      msgs)))

(defun get-line-style (text)
  "Determines croatoan attributes based on content patterns."
  (cond
    ((uiop:string-prefix-p "*" text) '(:bold :yellow))
    ((uiop:string-prefix-p "⬆" text) '(:cyan))
    ((uiop:string-prefix-p "🤔" text) '(:italic))
    ((uiop:string-prefix-p "ERROR" text) '(:bold :red))
    (t nil)))

(defun render-chat (win)
  "Renders the chat history with scrolling and styling."
  (clear win)
  (let* ((h (height win))
         (view-height (- h 2))
         (history-len (length *chat-history*))
         (start-idx *scroll-index*)
         (end-idx (min history-len (+ start-idx view-height)))
         (slice (reverse (subseq *chat-history* start-idx end-idx))))
    (loop for msg in slice
          for i from 1
          do (let ((style (get-line-style msg)))
               (add-string win (format nil "│ ~a" msg) :y i :x 1 :attributes style)))
    (refresh win)))

(defun handle-backspace ()
  "Deletes last character from input buffer."
  (when (> (fill-pointer *input-buffer*) 0)
    (decf (fill-pointer *input-buffer*))))

(defun handle-return (stream)
  "Process input buffer as message or command."
  (let ((cmd (coerce *input-buffer* 'string)))
    (setf (fill-pointer *input-buffer*) 0)
    (when (> (length cmd) 0)
      (enqueue-msg (format nil "⬆ ~a" cmd))
      (when (and stream (open-stream-p stream))
        (format stream "~a" (opencortex:frame-message (list :TYPE :EVENT 
                                                           :META (list :SOURCE :tui)
                                                           :PAYLOAD (list :SENSOR :user-input :TEXT cmd))))
        (finish-output stream)))
    (when (string= cmd "/exit") (setf *is-running* nil))
    (when (string= cmd "/clear") (setf *chat-history* nil))))

(defun main ()
  "Initializes ncurses and starts the TUI event loop."
  (handler-case
      (setf *socket* (usocket:socket-connect *daemon-host* *daemon-port*))
    (error (e) (format t "Offline: ~a~%" e) (return-from main)))
  (setf *stream* (usocket:socket-stream *socket*))
  
  (unwind-protect
      (with-screen (scr :input-echoing nil :input-blocking nil :enable-colors t)
        (let* ((h (height scr)) (w (width scr)))
          (unless (and h w)
             (error "Screen dimensions are NIL: h=~a, w=~a" h w))
          (let ((chat-win (make-instance 'window :height (- h 5) :width (- w 2) :position '(1 1) :border t))
                (input-win (make-instance 'window :height 1 :width (- w 2) :position (list (- h 2) 1) :border t)))
          
          (setf (input-blocking input-win) nil)
          
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
    (setf *is-running* nil)
    (when *socket* (ignore-errors (usocket:socket-close *socket*)))))
