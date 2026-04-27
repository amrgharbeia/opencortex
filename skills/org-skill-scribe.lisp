(in-package :opencortex)

(defvar *scribe-last-checkpoint* 0
  "The universal-time of the last successful distillation run.")

(defun scribe-load-state ()
  "Loads the scribe checkpoint from the state directory."
  (let ((state-file (uiop:merge-pathnames* "state/scribe-checkpoint.lisp" (asdf:system-source-directory :opencortex))))
    (if (uiop:file-exists-p state-file)
        (setf *scribe-last-checkpoint* (read-from-string (uiop:read-file-string state-file)))
        (setf *scribe-last-checkpoint* 0))))

(defun scribe-save-state ()
  "Saves the current universal-time as the new checkpoint."
  (let ((state-file (uiop:merge-pathnames* "state/scribe-checkpoint.lisp" (asdf:system-source-directory :opencortex))))
    (ensure-directories-exist state-file)
    (with-open-file (out state-file :direction :output :if-exists :supersede)
      (format out "~a" (get-universal-time)))))

(defun scribe-get-distillable-nodes ()
  "Returns a list of org-objects from the daily/ folder that require distillation."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (let* ((attrs (org-object-attributes obj))
                      (tags (getf attrs :TAGS))
                      (type (org-object-type obj))
                      (version (org-object-version obj)))
                 (when (and (eq type :HEADLINE)
                            (> version *scribe-last-checkpoint*)
                            (not (member "@personal" tags :test #'string-equal)))
                   (push obj results))))
             *memory*)
    results))

(defun probabilistic-skill-scribe (context)
  "Generates the extraction prompt for the Scribe."
  (let* ((payload (getf context :payload))
         (nodes (scribe-get-distillable-nodes)))
    (if nodes
        (let ((text-to-process ""))
          (dolist (node nodes)
            (setf text-to-process (concatenate 'string text-to-process 
                                               (format nil "ID: ~a~%TITLE: ~a~%CONTENT: ~a~%---~%" 
                                                       (org-object-id node)
                                                       (getf (org-object-attributes node) :TITLE)
                                                       (org-object-content node)))))
          (format nil "DISTILLATION TASK:
Below are raw chronological logs from my daily journal.
Extract ATOMIC EVERGREEN NOTES from this text.

RULES:
1. One note per distinct concept.
2. Output a list of Lisp plists: ((:title \"...\" :content \"...\" :source-id \"...\") ...)
3. The content should be in Org-mode format.
4. Keep titles descriptive and snake_case.

TEXT:
~a" text-to-process))
        nil)))

(defun scribe-commit-notes (proposals)
  "Writes proposed atomic notes to the notes/ directory. Appends if the note exists."
  (let ((notes-dir (uiop:merge-pathnames* "notes/" (asdf:system-source-directory :opencortex))))
    (ensure-directories-exist notes-dir)
    (dolist (note proposals)
      (let* ((title (getf note :title))
             (content (getf note :content))
             (source-id (getf note :source-id))
             (filename (format nil "~a.org" (string-downcase (cl-ppcre:regex-replace-all " " title "_"))))
             (path (merge-pathnames filename notes-dir)))
        (if (uiop:file-exists-p path)
            (with-open-file (out path :direction :output :if-exists :append)
              (format out "~%~%* Appended insight from ~a~%~a" source-id content))
            (with-open-file (out path :direction :output :if-exists :supersede)
              (format out ":PROPERTIES:~%:ID: ~a~%:SOURCE_ID: ~a~%:END:~%#+TITLE: ~a~%~%~a" 
                      (org-id-new) source-id title content)))
        (harness-log "SCRIBE: Processed evergreen note ~a" filename)))))

(defun verify-skill-scribe (action context)
  "Executes the note creation and marks source nodes as distilled."
  (declare (ignore context))
  (let ((data (cond ((and (listp action) (eq (getf action :type) :REQUEST))
                     (getf (getf action :payload) :payload))
                    ((and (listp action) (not (member (getf action :type) '(:LOG :EVENT))))
                     action)
                    (t nil))))
    (when data
      (harness-log "SCRIBE: Committing ~a atomic notes..." (length data))
      (scribe-commit-notes data)
      (scribe-save-state)
      (harness-log "SCRIBE: Distillation complete.")
      ;; Return a log event to stop the loop
      (list :type :LOG :payload (list :text "Distillation successful.")))))

(defskill :skill-scribe
  :priority 50
  :trigger (lambda (ctx)
             (let* ((payload (getf ctx :payload))
                    (sensor (getf payload :sensor)))
               (and (eq sensor :heartbeat)
                    ;; Only run once per hour to check if we need to distill
                    (> (- (get-universal-time) *scribe-last-checkpoint*) 3600)
                    (scribe-get-distillable-nodes))))
  :probabilistic #'probabilistic-skill-scribe
  :deterministic #'verify-skill-scribe)

(scribe-load-state)
