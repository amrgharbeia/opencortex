(in-package :org-agent)

(defvar *actuator-registry* (make-hash-table :test 'equal))

(defun register-actuator (name fn) 
  "Registers an actuator function. Actuators receive: (ACTION CONTEXT)."
  (setf (gethash name *actuator-registry*) fn))

(defun dispatch-action (action context)
  "Routes an approved action to its registered physical actuator."
  (when (and action (listp action))
    (let* ((target (or (ignore-errors (getf action :target)) :emacs)) 
           (actuator-fn (gethash target *actuator-registry*)))
      (if actuator-fn 
          (funcall actuator-fn action context) 
          (harness-log "ACT ERROR: No actuator for ~a" target)))))

(defun execute-system-action (action context)
  "Processes internal harness commands like skill creation."
  (declare (ignore context))
  (let* ((payload (ignore-errors (getf action :payload))) (cmd (ignore-errors (getf payload :action))))
    (case cmd
      (:eval (let ((code (getf payload :code)))
               (eval (read-from-string code))))
      (:create-skill (let* ((filename (getf payload :filename)) (content (getf payload :content))
                            (skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :org-agent))) (full-path (merge-pathnames filename skills-dir)))
                       (with-open-file (out full-path :direction :output :if-exists :supersede) (write-string content out))
                       (load-skill-from-org full-path)))
      (:message (harness-log "ACT [System]: ~a" (getf payload :text)))
      (t (harness-log "ACT ERROR [System]: Unknown command ~s" cmd)))))

(defun act-gate (signal)
  "Final Stage: Actuation and feedback generation."
  (let* ((approved (getf signal :approved-action))
         (type (getf signal :type))
         (depth (getf signal :depth 0))
         (feedback nil))
    (case type
      (:REQUEST (dispatch-action signal signal))
      (:EVENT 
       (when approved
         (let* ((payload (getf approved :payload))
                (target (getf approved :target))
                (action (or (getf payload :action) (getf approved :action)))
                (tool-name (or (getf payload :tool) (getf approved :tool)))
                (tool-args (or (getf payload :args) (getf approved :args))))
           (if (and (eq target :tool) (eq action :call))
               (let ((tool (gethash (string-downcase (string tool-name)) *cognitive-tools*)))
                 (if tool
                     (handler-case
                         (let* ((clean-args (if (and (listp tool-args) (listp (car tool-args))) (car tool-args) tool-args))
                                (result (funcall (cognitive-tool-body tool) clean-args)))
                           (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                                :payload (list :sensor :tool-output :result result :tool tool-name))))
                       (error (c)
                         (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                              :payload (list :sensor :tool-error :tool tool-name :message (format nil "~a" c))))))
                     (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                          :payload (list :sensor :tool-error :message "Tool not found")))))
               (let ((result (dispatch-action approved signal)))
                 (when (and result (not (member target '(:emacs :system-message))))
                   (setf feedback (list :type :EVENT :depth (1+ depth) :reply-stream (getf signal :reply-stream)
                                        :payload (list :sensor :tool-output :result result :tool approved))))))))))
    (setf (getf signal :status) :acted)
    feedback))
