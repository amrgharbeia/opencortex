(in-package :opencortex)

(defun context-query-store (&key tag todo-state type)
  "Filters the Memory based on tags, todo states, or types."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (let* ((attrs (org-object-attributes obj)) (state (getf attrs :TODO-STATE)) (match t))
                 (when (and type (not (eq (org-object-type obj) type))) (setf match nil))
                 (when tag (unless (search tag (format nil "~a" (getf attrs :TAGS)) :test #'string-equal) (setf match nil)))
                 (when (and todo-state (not (equal state todo-state))) (setf match nil))
                 (when match (push obj results))))
             *memory*)
    results))

(defun context-get-active-projects ()
  "Returns headlines tagged as 'project' that are not yet marked DONE."
  (remove-if (lambda (obj) (equal (getf (org-object-attributes obj) :TODO-STATE) "DONE"))
             (context-query-store :tag "project" :type :HEADLINE)))

(defun context-get-recent-completed-tasks () 
  "Retrieves recently finished tasks from the store."
  (context-query-store :todo-state "DONE" :type :HEADLINE))

(defun context-list-all-skills ()
  "Provides a sorted overview of currently loaded system capabilities."
  (let ((results nil))
    (maphash (lambda (name skill)
               (declare (ignore name))
               (push (list :name (skill-name skill) :priority (skill-priority skill) :dependencies (skill-dependencies skill)) results))
             *skills-registry*)
    (sort results #'> :key (lambda (x) (getf x :priority)))))

(defun context-get-skill-source (skill-name)
  "Reads the raw literate source of a specific skill for inspection."
  (let* ((filename (format nil "~a.org" skill-name))
         (skills-dir-str (or (uiop:getenv "SKILLS_DIR") (namestring (merge-pathnames "notes/" (user-homedir-pathname)))))
         (skills-dir (uiop:ensure-directory-pathname (context-resolve-path skills-dir-str)))
         (full-path (merge-pathnames filename skills-dir)))
    (if (uiop:file-exists-p full-path) (uiop:read-file-string full-path) nil)))

(defun context-get-system-logs (&optional limit)
  "Retrieves the most recent lines from the harness's internal log."
  (let ((log-limit (or limit (ignore-errors (parse-integer (uiop:getenv "CONTEXT_LOG_LIMIT"))) 20)))
    (bt:with-lock-held (*logs-lock*)
      (let ((count (min log-limit (length *system-logs*)))) 
        (subseq *system-logs* 0 count)))))

(defun context-render-to-org (obj &key (depth 1) (foveal-id nil) semantic-threshold (foveal-vector nil))
  "Recursively renders an org-object and its children to an Org string using a Foveal-Peripheral Hybrid model."
  (let* ((id (org-object-id obj))
         (is-foveal (equal id foveal-id))
         (title (or (getf (org-object-attributes obj) :TITLE) "Untitled"))
         (content (org-object-content obj))
         (children (org-object-children obj))
         (stars (make-string depth :initial-element #\*))
         (obj-vector (org-object-vector obj))
         (threshold (or semantic-threshold (ignore-errors (read-from-string (uiop:getenv "CONTEXT_SEMANTIC_THRESHOLD"))) 0.75))
         (similarity (if (and foveal-vector obj-vector (not is-foveal))
                         (cosine-similarity foveal-vector obj-vector)
                         0.0))
         (is-semantically-relevant (>= similarity threshold))
         ;; We always render depth 1 and 2 (Projects and main tasks).
         ;; We always render the foveal node and its immediate children.
         ;; We render deeper nodes ONLY if they are semantically relevant.
         (should-render (or (<= depth 2) is-foveal is-semantically-relevant))
         (output ""))
    
    (when should-render
      (setf output (format nil "~a ~a~%:PROPERTIES:~%:ID: ~a~%" stars title id))
      (when is-semantically-relevant
        (setf output (concatenate 'string output (format nil ":SEMANTIC_SCORE: ~,2f~%" similarity))))
      (setf output (concatenate 'string output (format nil ":END:~%")))
      
      ;; Only include full body content if this is the Foveal focus or highly relevant
      (when (and content (or is-foveal is-semantically-relevant))
        (setf output (concatenate 'string output content (string #\Newline))))
      
      ;; Recursively render children
      (dolist (child-id children)
        (let ((child-obj (lookup-object child-id)))
          (when child-obj
            ;; If the current node is Foveal, its children should be rendered (depth effectively resets)
            (let ((next-foveal (if is-foveal child-id foveal-id)))
              (setf output (concatenate 'string output 
                                        (context-render-to-org child-obj 
                                                               :depth (1+ depth) 
                                                               :foveal-id next-foveal
                                                               :semantic-threshold threshold
                                                               :foveal-vector foveal-vector))))))))
    output))

(defun context-resolve-path (path-string)
  "Expands all environment variables ($VAR) within a path string."
  (if (and (stringp path-string) (search "$" path-string))
      (let ((result path-string))
        (ppcre:do-register-groups (var-name) ("\\$([A-Za-z0-9_]+)" path-string)
          (let ((var-val (uiop:getenv var-name)))
            (when var-val
              (setf result (ppcre:regex-replace (format nil "\\$~a" var-name) result var-val)))))
        result)
      path-string))

(defun context-assemble-global-awareness (&optional signal)
  "Produces a high-level skeletal outline of the current Memory for the LLM."
  (let* ((foveal-id (or (getf signal :foveal-focus) 
                        (ignore-errors (getf (getf signal :payload) :target-id))))
         (projects (context-get-active-projects))
         (output "GLOBAL MEMEX AWARENESS (Peripheral Vision):
"))
    (if projects
        (dolist (project projects)
          (setf output (concatenate 'string output
                                    (context-render-to-org project :foveal-id foveal-id))))
        (setf output (concatenate 'string output "No active projects found.~%")))
    output))
