(in-package :org-agent)

;;; ============================================================================
;;; CLOSOS-inspired Object Store
;;; ============================================================================
;;; This module implements the system's "Perceptual Memory." 
;;; Instead of treating Org files as flat text, we parse them into a relational
;;; graph of attributed Lisp objects. This allows for fast, deterministic 
;;; symbolic queries (System 2) that can inform neural suggestions (System 1).

(defvar *object-store* (make-hash-table :test 'equal)
  "The global, in-memory database of all ingested Org-mode elements.
   Keys are unique IDs (from Org properties or generated), values are org-object structs.")

(defstruct org-object
  "The atomic unit of information in the Neurosymbolic Lisp Machine.
   This mirrors the hierarchical structure of an Org-mode file but in a 
   format optimized for Lisp manipulation."
  id         ; A unique identifier (e.g., a UUID from an :ID: property)
  type       ; The Org element type (e.g., :HEADLINE, :PARAGRAPH, :PLAIN-LIST)
  attributes ; A property list of metadata (e.g., :TITLE, :TAGS, :TODO-STATE)
  content    ; The raw text or non-element data within the node
  vector     ; The semantic embedding vector (System 1 memory)
  parent-id  ; A pointer to the parent object's ID for tree traversal
  children   ; A list of IDs for all immediate child nodes
  version    ; A timestamp or counter used for cache invalidation
  last-sync  ; The universal-time when this object was last updated from Emacs
  )

(defun ingest-ast (ast &optional parent-id)
  "Recursively transforms a nested Org AST (Abstract Syntax Tree) into a 
   relational graph within the *object-store*.
   
   AST: A property list representing an Org element (from org-agent.el).
   PARENT-ID: The ID of the parent element, used during recursion.
   
   Returns the ID of the ingested node."
  (let* ((type (getf ast :type))
         (props (getf ast :properties))
         ;; We prioritize existing Org IDs. If none exists, we generate a 
         ;; temporary ID to maintain the object's identity in the store.
         (id (or (getf props :ID) 
                 (format nil "temp-~a" (get-universal-time))))
         (contents (getf ast :contents))
         ;; Extract raw text for embedding if it's a headline
         (raw-content (when (eq type :HEADLINE)
                        (format nil "~a~%~a" 
                                (getf props :TITLE)
                                (or (cl:getf ast :raw-content) ""))))
         (child-ids nil))
    
    ;; Depth-first ingestion: Recurse into children first to gather their IDs.
    (dolist (child contents)
      (when (listp child)
        (push (ingest-ast child id) child-ids)))
    
    ;; Create or overwrite the object in the hash table. 
    ;; This is a 'late-binding' update—if the ID exists, we update its state.
    (let ((obj (make-org-object 
                :id id
                :type type
                :attributes props
                :content raw-content
                :vector (when raw-content (get-embedding raw-content))
                :parent-id parent-id
                :children (nreverse child-ids) ; Maintain document order
                :version (get-universal-time)
                :last-sync (get-universal-time))))
      (setf (gethash id *object-store*) obj)
      id)))

(defvar *object-store-snapshots* nil
  "A history of previous *object-store* states for rollback/time-travel.")

(defun copy-org-object (obj)
  "Creates a shallow copy of an org-object struct.
   Used during snapshotting."
  (make-org-object 
   :id (org-object-id obj)
   :type (org-object-type obj)
   :attributes (copy-list (org-object-attributes obj))
   :content (org-object-content obj)
   :vector (org-object-vector obj)
   :parent-id (org-object-parent-id obj)
   :children (copy-list (org-object-children obj))
   :version (org-object-version obj)
   :last-sync (org-object-last-sync obj)))

(defun snapshot-object-store ()
  "Creates a deep-copy of the current object store hash table.
   Allows for 'Interactive Steering' and state rollback."
  (let ((snapshot (make-hash-table :test 'equal)))
    (maphash (lambda (id obj)
               (setf (gethash id snapshot) (copy-org-object obj)))
             *object-store*)
    (push (list :timestamp (get-universal-time) :data snapshot) *object-store-snapshots*)
    ;; Keep only the last 20 snapshots to prevent memory leaks
    (when (> (length *object-store-snapshots*) 20)
      (setf *object-store-snapshots* (subseq *object-store-snapshots* 0 20)))
    (kernel-log "MEMORY - Object Store snapshot created.")))

(defun rollback-object-store (&optional (index 0))
  "Restores the Object Store to a previous state."
  (let ((snapshot (nth index *object-store-snapshots*)))
    (if snapshot
        (progn
          (setf *object-store* (getf snapshot :data))
          (kernel-log "MEMORY - Object Store rolled back to snapshot ~a" index))
        (kernel-log "MEMORY ERROR - Snapshot ~a not found." index))))

(defun lookup-object (id)
  "Retrieves an org-object from the store by its unique ID. Returns NIL if not found."
  (gethash id *object-store*))

(defun list-objects-by-type (type)
  "Returns a list of all objects matching a specific type (e.g., :HEADLINE).
   Useful for bulk operations across all loaded files."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (when (eq (org-object-type obj) type)
                 (push obj results)))
             *object-store*)
    results))

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

;;; ============================================================================
;;; AST Helper Functions
;;; ============================================================================

(defun find-headline-missing-id (ast)
  "A recursive utility to find any headline element that lacks a unique :ID: property.
   This is used by normalization skills to ensure data integrity."
  (when (listp ast)
    (if (and (eq (getf ast :type) :HEADLINE)
             (not (getf (getf ast :properties) :ID)))
        ast
        (cl:some #'find-headline-missing-id (getf ast :contents)))))

(defun file-name-nondirectory (path)
  "Extracts the filename from a full path (portable across OSs)."
  (let ((pos (position #\/ path :from-end t)))
    (if pos (subseq path (1+ pos)) path)))

