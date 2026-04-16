(in-package :opencortex)

(defvar *default-actuator* :cli)
(defvar *silent-actuators* '(:cli :system-message :emacs))

(defun initialize-actuators ()
  "Loads actuator routing defaults from environment variables and registers core harness actuators."
  (let ((def (uiop:getenv "DEFAULT_ACTUATOR"))
        (silent (uiop:getenv "SILENT_ACTUATORS")))
    (when def
      (setf *default-actuator* (intern (string-upcase def) "KEYWORD")))
    (when silent
      (setf *silent-actuators*
            (mapcar (lambda (s) (intern (string-upcase (string-trim '(#\Space) s)) "KEYWORD"))
                    (str:split "," silent)))))
  
  ;; Register core harness actuators
  (register-actuator :system #'execute-system-action)
  (register-actuator :tool #'execute-tool-action))

(defun dispatch-action (action context)
  "Routes an approved action to its registered physical actuator."
  (when (and action (listp action))
    (let* ((target (or (ignore-errors (getf action :target)) *default-actuator*)) 
           (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn 
          (funcall actuator-fn action context) 
          (harness-log "ACT ERROR: No actuator for ~a" target)))))

(defun execute-system-action (action context)
  "Processes internal harness commands. (ACTUATOR)"
  (declare (ignore context))
  (let* ((payload (ignore-errors (getf action :payload))) 
         (cmd (ignore-errors (getf payload :action))))
    (case cmd
      (:eval (let ((code (getf payload :code)))
               (eval (read-from-string code))))
      (:create-skill (let* ((filename (getf payload :filename)) (content (getf payload :content))
                            (skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :opencortex))) 
                            (full-path (merge-pathnames filename skills-dir)))
                       (with-open-file (out full-path :direction :output :if-exists :supersede) (write-string content out))
                       (load-skill-from-org full-path)))
      (:message (harness-log "ACT [System]: ~a" (getf payload :text)))
      (t (harness-log "ACT ERROR [System]: Unknown command ~s" cmd)))))

(defun execute-tool-action (action context)
  "Executes a registered cognitive tool. (ACTUATOR)"
  (let* ((payload (getf action :payload))
         (tool-name (getf payload :tool))
         (tool-args (getf payload :args))
         (depth (getf context :depth 0))
         (tool (gethash (string-downcase (string tool-name)) *cognitive-tools*)))
    (if tool
        (handler-case
            (let* ((clean-args (if (and (listp tool-args) (listp (car tool-args))) (car tool-args) tool-args))
                   (result (funcall (cognitive-tool-body tool) clean-args)))
              (list :type :EVENT :depth (1+ depth) :reply-stream (getf context :reply-stream)
                    :payload (list :sensor :tool-output :result result :tool tool-name)))
          (error (c)
            (list :type :EVENT :depth (1+ depth) :reply-stream (getf context :reply-stream)
                  :payload (list :sensor :tool-error :tool tool-name :message (format nil "~a" c)))))
        (list :type :EVENT :depth (1+ depth) :reply-stream (getf context :reply-stream)
              :payload (list :sensor :tool-error :message "Tool not found")))))

(defun act-gate (signal)
  "Final Stage: Actuation and feedback generation."
  (let* ((approved (getf signal :approved-action))
         (type (getf signal :type))
         (feedback nil))
    
    ;; 1. Last-Mile Safety Check (The Bouncer & Deterministic Gates)
    (when approved
      (let ((verified (deterministic-verify approved signal)))
        (if (and (listp verified) (member (getf verified :type) '(:LOG :EVENT :log :event)))
            (progn
              (harness-log "ACT BLOCKED: Action failed last-mile deterministic check.")
              (setf (getf signal :approved-action) nil)
              (setf approved nil)
              (setf feedback verified))
            (progn
              (setf (getf signal :approved-action) verified)
              (setf approved verified)))))

    ;; 2. Actuation Logic
    (case type
      (:REQUEST (dispatch-action signal signal))
      (:EVENT 
       (when approved
         (let* ((target (getf approved :target))
                (result (dispatch-action approved signal)))
           ;; If the actuator returns a signal (like :tool-output), it becomes the feedback.
           ;; Otherwise, generate tool-output feedback for non-silent actuators.
           (cond ((and (listp result) (member (getf result :type) '(:EVENT :LOG)))
                  (setf feedback result))
                 ((and result (not (member target *silent-actuators*)))
                  (setf feedback (list :type :EVENT :depth (1+ (getf signal :depth 0)) 
                                       :reply-stream (getf signal :reply-stream)
                                       :payload (list :sensor :tool-output :result result :tool approved)))))))))
    
    (setf (getf signal :status) :acted)
    feedback))
