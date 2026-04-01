(in-package :org-agent)

;;; ============================================================================
;;; Context API (System 1 Peripheral Vision)
;;; ============================================================================
;;; These functions provide the 'peripheral vision' for the LLM. 
;;; When building a prompt, a skill can call these functions to gather 
;;; relevant facts from the Object Store, preventing 'tunnel vision'.

(defun context-query-store (&key tag todo-state type)
  "A high-level search engine for the Object Store.
   TAG: String to search for in the :TAGS property.
   TODO-STATE: The string state (e.g., 'TODO', 'DONE', 'WAITING').
   TYPE: The keyword type (e.g., :HEADLINE).
   
   Returns a list of org-object structs that satisfy ALL provided criteria."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (let* ((attrs (org-object-attributes obj))
                      (obj-type (org-object-type obj))
                      (tags (getf attrs :TAGS))
                      (state (getf attrs :TODO-STATE))
                      (match t))
                 ;; Filter by Type
                 (when (and type (not (eq obj-type type))) (setf match nil))
                 
                 ;; Filter by Tag (Org tags are often stored as a colon-delimited string like ':work:urgent:')
                 (when tag 
                   (let ((tags-str (format nil "~a" tags)))
                     (unless (search tag tags-str :test #'string-equal)
                       (setf match nil))))
                 
                 ;; Filter by TODO State
                 (when (and todo-state (not (equal state todo-state))) (setf match nil))
                 
                 (when match (push obj results))))
             *object-store*)
    results))

(defun context-get-active-projects ()
  "Retrieves all headlines tagged with 'project' that are not yet complete.
   This allows the agent to understand what the user is currently working on."
  (let ((projects (context-query-store :tag "project" :type :HEADLINE)))
    (remove-if (lambda (obj) (equal (getf (org-object-attributes obj) :TODO-STATE) "DONE"))
               projects)))

(defun context-get-recent-completed-tasks ()
  "Retrieves tasks that have been successfully finished.
   Used to give the LLM context about the user's 'momentum' and recent wins."
  (context-query-store :todo-state "DONE" :type :HEADLINE))

;;; ============================================================================
;;; Introspection API (Self-Awareness)
;;; ============================================================================
;;; These functions allow the agent to see its own internal configuration,
;;; such as its skill priorities and source code. This is critical for 
;;; Phase 3 (Self-Editing) and autonomous priority negotiation.

(defun context-list-all-skills ()
  "Returns a list of plists for all currently registered skills.
   Each plist contains :name, :priority, and :dependencies.
   This allows System 1 to understand the current 'Skill Graph'."
  (let ((results nil))
    (maphash (lambda (name skill)
               (declare (ignore name))
               (push (list :name (skill-name skill)
                           :priority (skill-priority skill)
                           :dependencies (skill-dependencies skill))
                     results))
             *skills-registry*)
    (sort results #'> :key (lambda (x) (getf x :priority)))))

(defun context-get-skill-source (skill-name)
  "Reads the raw Org-mode source code of a specific skill.
   Returns the file content as a string, or NIL if the file is missing."
  (let* ((filename (format nil "~a.org" skill-name))
         (skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :org-agent)))
         (full-path (merge-pathnames filename skills-dir)))
    (if (uiop:file-exists-p full-path)
        (uiop:read-file-string full-path)
        nil)))

(defun context-get-system-logs (&optional (limit 20))
  "Returns the most recent N lines from the kernel's execution history.
   Allows the agent to 'perceive pain' (errors/rejections) and trigger self-repair."
  (bt:with-lock-held (*logs-lock*)
    (let ((count (min limit (length *system-logs*))))
      (subseq *system-logs* 0 count))))

(defun context-get-skill-telemetry (skill-name)
  "Returns performance metrics for a specific skill.
   Returns a plist with :executions, :total-time, and :failures."
  (bt:with-lock-held (*telemetry-lock*)
    (gethash (string-downcase skill-name) *skill-telemetry*)))

(defun context-filter-sparse-tree (ast predicate)
  "Recursively prunes an Org AST, keeping only nodes that match PREDICATE 
   and their parent hierarchies. Reduces token waste by removing noise."
  (if (listp ast)
      (let* ((type (getf ast :type))
             (contents (getf ast :contents))
             ;; Recursively filter children
             (filtered-contents 
              (remove-if #'null 
                         (mapcar (lambda (c) (context-filter-sparse-tree c predicate))
                                 contents))))
        
        (if (or (funcall predicate ast)
                (not (null filtered-contents)))
            ;; If this node matches OR has matching children, keep it
            (let ((new-ast (copy-list ast)))
              (setf (getf new-ast :contents) filtered-contents)
              new-ast)
            ;; Otherwise, prune this entire branch
            nil))
      ;; If it's a string (leaf content), keep it if the predicate says so, 
      ;; but usually we keep it if the parent headline matches.
      nil))

(defun context-resolve-path (path-string)
  "Resolves environment variables in a path string (e.g., '$PROJECTS_DIR/my-proj').
   This ensures project links remain valid even if base directories are moved."
  (if (and (stringp path-string) (uiop:string-prefix-p "$" path-string))
      (let* ((parts (uiop:split-string path-string :separator '(#\/)))
             (var-name (subseq (car parts) 1)) ; Strip the '$'
             (var-val (org-agent::get-env var-name))
             (remaining (cl:reduce (lambda (a b) (format nil "~a/~a" a b)) (cdr parts))))
        (if var-val
            ;; Strip any extra quotes that cl-dotenv might have preserved
            (let ((clean-val (string-trim '(#\" #\Space) var-val)))
              (format nil "~a/~a" (string-right-trim "/" clean-val) remaining))
            path-string))
      path-string))
