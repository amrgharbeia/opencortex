(in-package :cl-user)
(defpackage :opencortex.tui
  (:use :cl :croatoan)
  (:export :main))
(in-package :opencortex.tui)

(defvar *daemon-host* "127.0.0.1")
(defvar *daemon-port* 9105)
(defvar *socket* nil)
(defvar *stream* nil)
(defvar *chat-history* (list))
(defvar *status-text* "Connecting...")
(defvar *input-buffer* (make-array 0 :element-type 'char :fill-pointer 0 :adjustable t))
(defvar *is-running* t)
(defvar *queue-lock* (bordeaux-threads:make-lock))
(defvar *incoming-msgs* nil)

(defun enqueue-msg (msg)
  (bordeaux-threads:with-lock-held (*queue-lock*)
    (push msg *incoming-msgs*)))

(defun dequeue-msgs ()
  (bordeaux-threads:with-lock-held (*queue-lock*)
    (let ((msgs (nreverse *incoming-msgs*)))
      (setf *incoming-msgs* nil)
      msgs)))

(defun clean-keywords (msg)
  (if (listp msg)
      (let ((clean nil))
        (loop for (k v) on msg by #'cddr
              do (push (intern (string k) :keyword) clean)
                 (push v clean))
        (nreverse clean))
      msg))

(defun format-payload (payload)
  "Extracts human-readable text from a protocol payload, handling nested tool calls."
  (let* ((action (getf payload :ACTION))
         (text (getf payload :TEXT))
         (msg (getf payload :MESSAGE))
         (tool (getf payload :TOOL))
         (prompt (getf payload :PROMPT))
         (args (getf payload :ARGS))
         (result (getf payload :RESULT)))
    (cond (text text)
          (msg msg)
          ((eq action :MESSAGE) (getf payload :TEXT))
          ((and tool prompt) (format nil "THOUGHT [~a]: ~a" tool prompt))
          ((and tool args) 
           (let ((inner-prompt (or (getf args :PROMPT) (getf args :TEXT))))
             (if inner-prompt
                 (format nil "THOUGHT [~a]: ~a" tool inner-prompt)
                 (format nil "CALL [~a] (ARGS: ~s)" tool args))))
          (result (format nil "RESULT: ~a" result))
          (t (format nil "~s" payload)))))

(defun listen-thread ()
  (loop while *is-running* do
    (handler-case
        (when (and *stream* (open-stream-p *stream*))
          (let ((raw-msg (opencortex:read-framed-message *stream*)))
            (unless (member raw-msg '(:eof :error))
              (let* ((msg (clean-keywords raw-msg))
                     (type (or (getf msg :TYPE) (getf msg :type)))
                     (payload (or (getf msg :PAYLOAD) (getf msg :payload))))
                (cond ((and (listp msg) (eq type :EVENT))
                       (let ((action (or (getf payload :ACTION) (getf payload :action)))
                             (text (or (getf payload :TEXT) (getf payload :text) (getf payload :MESSAGE) (getf payload :message))))
                         (cond ((eq action :handshake) (setf *status-text* "Ready"))
                               (text (enqueue-msg (format nil "SYSTEM: ~a" text))))))
                      ((and (listp msg) (eq type :STATUS))
                       (setf *status-text* (format nil "[Scribe: ~a] [Gardener: ~a]" 
                                                   (or (getf msg :SCRIBE) (getf msg :scribe))
                                                   (or (getf msg :GARDENER) (getf msg :gardener)))))
                      ((and (listp msg) (member type '(:REQUEST :RESPONSE :LOG)))
                       (let ((formatted (format-payload payload)))
                         (when formatted (enqueue-msg formatted))))
                      ((and (listp msg) (eq type :EVENT) (eq (getf payload :SENSOR) :TOOL-OUTPUT))
                       (let ((formatted (format-payload payload)))
                         (when formatted (enqueue-msg formatted))))
                      (t (harness-log "TUI: Ignored unknown type ~a" type)))))
            (when (eq raw-msg :eof) (setf *is-running* nil))
            (when (eq raw-msg :error) (setf *status-text* "Protocol Error"))))
      (error (c) (setf *status-text* (format nil "Net Error: ~a" c)) (setf *is-running* nil)))
    (sleep 0.05)))

(defun main ()
  (handler-case
      (setf *socket* (usocket:socket-connect *daemon-host* *daemon-port*))
    (error (e) (format t "Error connecting: ~a~%" e) (return-from main)))
  (setf *stream* (usocket:socket-stream *socket*))
  (bordeaux-threads:make-thread #'listen-thread :name "tui-listener")
  
  (unwind-protect
      (with-screen (scr :input-echoing nil :input-blocking nil :enable-colors t :cursor-visible t)
        (let* ((h (height scr))
               (w (width scr))
               (chat-win (make-instance 'window :height (- h 2) :width w :position (list 0 0)))
               (status-win (make-instance 'window :height 1 :width w :position (list (- h 2) 0)))
               (input-win (make-instance 'window :height 1 :width w :position (list (- h 1) 0)))
               (last-status nil))
          
          (setf (function-keys-enabled-p input-win) t)
          (setf (input-blocking input-win) nil)

          (loop while *is-running* do
            ;; 1. Handle incoming messages
            (let ((new-msgs (dequeue-msgs)))
              (when new-msgs
                (dolist (msg new-msgs)
                  (push msg *chat-history*)
                  (setf *chat-history* (subseq *chat-history* 0 (min (length *chat-history*) 500))))
                
                (clear chat-win)
                (let ((line-num 0))
                  (dolist (m (reverse (subseq *chat-history* 0 (min (length *chat-history*) (- h 3)))))
                    (add-string chat-win m :y line-num :x 0)
                    (incf line-num)))
                (refresh chat-win)))

            ;; 2. Render Status Bar ONLY if changed
            (unless (equal *status-text* last-status)
              (clear status-win)
              (add-string status-win *status-text* :attributes '(:reverse))
              (refresh status-win)
              (setf last-status *status-text*))

            ;; 3. Handle Keyboard Input
            (let* ((event (get-wide-event input-win))
                   (ch (and event (typep event 'event) (event-key event))))
              (when ch
                (cond
                  ((or (eq ch #\Newline) (eq ch #\Return))
                   (let ((cmd (coerce *input-buffer* 'string)))
                     (setf (fill-pointer *input-buffer*) 0)
                     (when (> (length cmd) 0)
                       ;; Local Echo
                       (enqueue-msg (concatenate 'string "> " cmd))
                       ;; Send to Brain
                       (let ((framed (opencortex:frame-message (list :TYPE :EVENT 
                                                                    :META (list :SOURCE :tui :SESSION-ID "default")
                                                                    :PAYLOAD (list :SENSOR :user-input :TEXT cmd)))))
                         (format *stream* "~a" framed)
                         (finish-output *stream*)))
                     (when (string= cmd "/exit") (setf *is-running* nil))))
                  ((or (eq ch :backspace) (eq ch #\Backspace) (eq ch #\Rubout) (eq ch #\Del))
                   (when (> (length *input-buffer*) 0)
                     (decf (fill-pointer *input-buffer*))))
                  ((characterp ch)
                   (vector-push-extend ch *input-buffer*))))
              
              (clear input-win)
              (add-string input-win (concatenate 'string "> " (coerce *input-buffer* 'string)))
              (move input-win 0 (+ 2 (length *input-buffer*)))
              (refresh input-win))
            
            (sleep 0.02))))
    (setf *is-running* nil)
    (when *socket* (usocket:socket-close *socket*))))
