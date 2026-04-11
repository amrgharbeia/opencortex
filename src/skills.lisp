(in-package :org-agent)

(defstruct skill name priority dependencies trigger-fn neuro-prompt symbolic-fn)

(defvar *skill-catalog* (make-hash-table :test 'equal)
  "A stateful tracking table for all skill files discovered in the environment.")

(defstruct skill-entry 
  filename 
  (status :discovered) ;; :discovered, :loading, :ready, :failed
  error-log
  (load-time 0))

(defun find-triggered-skill (context)
  "Returns the highest priority skill whose trigger condition matches the context."
  (let ((matched-skills nil))
    (maphash (lambda (name skill)
               (declare (ignore name))
               (let ((trigger-fn (skill-trigger-fn skill)))
                 (when (and trigger-fn (funcall trigger-fn context))
                   (push skill matched-skills))))
             *skills-registry*)
    (first (sort matched-skills #'> :key #'skill-priority))))

(defmacro defskill (name &key priority dependencies trigger neuro symbolic)
  `(setf (gethash ,(string-downcase (string name)) *skills-registry*)
         (make-skill :name ,(string-downcase (string name)) :priority (or ,priority 10) :dependencies ,dependencies :trigger-fn ,trigger :neuro-prompt ,neuro :symbolic-fn ,symbolic)))

(defun load-skill-from-org (path)
  "Extracts Lisp source from an Org file and evaluates it."
  (let ((skill-name (pathname-name path)))
    (handler-case
        (let ((source (uiop:read-file-string path)))
          (cl-ppcre:do-register-groups (code) ("#\\+begin_src lisp.*\\n([\\s\\S]*?)\\n#\\+end_src" source)
            (let ((*package* (find-package :org-agent)))
              (eval (read-from-string (concatenate 'string "(progn " code ")")))))
          (setf (gethash skill-name *skill-catalog*) (make-skill-entry :filename path :status :ready :load-time (get-universal-time)))
          (kernel-log "SKILL [Loader] - Successfully loaded ~a" skill-name))
      (error (c)
        (kernel-log "SKILL ERROR [Loader] - Failed to load ~a: ~a" skill-name c)
        (setf (gethash skill-name *skill-catalog*) (make-skill-entry :filename path :status :failed :error-log (format nil "~a" c)))))))

(defun initialize-all-skills ()
  "Discovers and loads all .org skills from the project directory."
  (let ((skill-dir (or (uiop:getenv "SKILLS_DIR") "projects/org-agent/skills/")))
    (ensure-directories-exist skill-dir)
    (dolist (path (uiop:directory-files skill-dir "*.org"))
      (load-skill-from-org path))))
