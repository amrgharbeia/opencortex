(in-package :opencortex)

(defvar *probabilistic-backends* (make-hash-table :test 'equal))

(defvar *provider-cascade* nil)

(defvar *model-selector-fn* nil)

(defvar *consensus-enabled-p* nil)

(defun register-probabilistic-backend (name fn)
  (setf (gethash name *probabilistic-backends*) fn))

(defun probabilistic-call (prompt &key
                                (system-prompt "You are the Probabilistic engine.")
                                (cascade nil)
                                (context nil))
  (let ((backends (or cascade *provider-cascade*)))
    (or (dolist (backend backends)
          (let ((backend-fn (gethash backend *probabilistic-backends*)))
            (when backend-fn
              (harness-log "PROBABILISTIC: Attempting backend ~a..." backend)
              (let* ((model (when *model-selector-fn*
                              (funcall *model-selector-fn* backend context)))
                     (result (if model
                                 (funcall backend-fn prompt system-prompt :model model)
                                 (funcall backend-fn prompt system-prompt))))
                (cond ((and (listp result) (eq (getf result :status) :success))
                       (return (getf result :content)))
                      ((stringp result)
                       (return result))
                      (t
                       (harness-log "PROBABILISTIC: Backend ~a failed: ~a"
                                   backend (getf result :message))))))))
        (list :type :LOG
              :payload (list :text "Neural Cascade Failure: All providers exhausted.")))))

(defun strip-markdown (text)
  (if (and text (stringp text))
      (let ((cleaned text))
        (setf cleaned (cl-ppcre:regex-replace-all "^```[a-z]*\\n" cleaned ""))
        (setf cleaned (cl-ppcre:regex-replace-all "\\n```$" cleaned ""))
        (setf cleaned (cl-ppcre:regex-replace-all "```" cleaned ""))
        (string-trim '(#\Space #\Newline #\Tab) cleaned))
      text))

(defun normalize-plist-keywords (plist)
  (when (listp plist)
    (loop for (k v) on plist by #'cddr
          collect (if (and (symbolp k) (not (keywordp k)))
                       (intern (string k) :keyword)
                       k)
          collect v)))

(defun think (context)
  (let* ((active-skill (find-triggered-skill context))
         (tool-belt (generate-tool-belt-prompt))
         (global-context (context-assemble-global-awareness))
         (system-logs (context-get-system-logs))
         (assistant-name (or (uiop:getenv "MEMEX_ASSISTANT") "Agent"))
         (rejection-trace (proto-get (proto-get context :payload) :rejection-trace))
         (prompt-generator (when active-skill (skill-probabilistic-prompt active-skill)))
         (raw-prompt (if prompt-generator
                         (funcall prompt-generator context)
                         (let ((p (proto-get (proto-get context :payload) :text)))
                           (if (and p (stringp p)) p "Maintain metabolic stasis."))))
         (reflection-feedback (if rejection-trace
                                  (format nil "~%~%PREVIOUS PROPOSAL REJECTED: ~a" rejection-trace)
                                  ""))
         (system-prompt (format nil "IDENTITY: ~a~a~%~%TOOLS:~%~a~%~%CONTEXT:~%~a~%~%LOGS:~%~a" 
                               assistant-name reflection-feedback tool-belt global-context system-logs)))
    (let* ((thought (probabilistic-call raw-prompt :system-prompt system-prompt :context context))
           (cleaned (strip-markdown thought)))
      (if (and cleaned (stringp cleaned) (> (length cleaned) 0) (char= (char cleaned 0) #\((char= (char cleaned 0) #\()))
          (handler-case
              (let ((parsed (read-from-string cleaned)))
                (if (listp parsed)
                    (normalize-plist-keywords parsed)
                    (list :TYPE :REQUEST :PAYLOAD (list :ACTION :MESSAGE :TEXT cleaned))))
            (error () (list :TYPE :REQUEST :PAYLOAD (list :ACTION :MESSAGE :TEXT cleaned))))
          (list :TYPE :REQUEST :PAYLOAD (list :ACTION :MESSAGE :TEXT (or cleaned "No response")))))))

(defun deterministic-verify (proposed-action context)
  (let ((current-action proposed-action)
        (skills nil))
    (maphash (lambda (name skill)
               (declare (ignore name))
               (when (skill-deterministic-fn skill)
                 (push skill skills)))
             *skills-registry*)
    (setf skills (sort skills #'> :key #'skill-priority))
    (dolist (skill skills)
      (let ((trigger (skill-trigger-fn skill))
            (gate (skill-deterministic-fn skill)))
        (when (or (null trigger) (ignore-errors (funcall trigger context)))
          (let ((next-action (funcall gate current-action context)))
            (when (and (listp next-action)
                       (member (proto-get next-action :type) '(:LOG :EVENT)))
              (harness-log "DETERMINISTIC: Intercepted by skill '~a'" (skill-name skill))
              (return-from deterministic-verify next-action))
            (setf current-action next-action)))))
    current-action))

(defun reason-gate (signal)
  (let* ((type (proto-get signal :type))
         (payload (proto-get signal :payload))
         (sensor (proto-get payload :sensor)))
    (unless (and (eq type :EVENT) (member sensor '(:user-input :chat-message)))
      (return-from reason-gate signal))
    (let ((retries 3)
          (current-signal (copy-tree signal))
          (last-rejection nil))
      (loop
        (when (<= retries 0)
          (setf (getf signal :approved-action) last-rejection)
          (setf (getf signal :status) :reasoned)
          (return signal))
        (when last-rejection
          (setf (getf (getf current-signal :payload) :rejection-trace) last-rejection))
        (let ((candidate (think current-signal)))
          (if (and candidate (listp candidate))
              (let ((verified (deterministic-verify candidate current-signal)))
                (if (member (getf verified :type) '(:LOG :EVENT))
                    (progn (decf retries) (setf last-rejection verified))
                    (progn
                      (setf (getf signal :approved-action) verified)
                      (setf (getf signal :status) :reasoned)
                      (return signal))))
              (progn
                (setf (getf signal :approved-action) nil)
                (setf (getf signal :status) :reasoned)
                (return signal))))))))
