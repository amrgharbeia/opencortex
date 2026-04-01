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
         ;; Lazy Embedding: Only embed if the headline has :EMBED: t property
         (raw-content (when (eq type :HEADLINE)
                        (format nil "~a~%~a" 
                                (getf props :TITLE)
                                (or (cl:getf ast :raw-content) ""))))
         (should-embed (and raw-content (equal (getf props :EMBED) "t")))
         (child-ids nil))
    
    ;; Depth-first ingestion: Recurse into children first to gather their IDs.
    (dolist (child contents)
      (when (listp child)
        (push (ingest-ast child id) child-ids)))
    
    ;; Create or overwrite the object in the hash table. 
    (let ((obj (make-org-object 
                :id id
                :type type
                :attributes props
                :content raw-content
                :vector (when should-embed (get-embedding raw-content))
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

;;; ================= ===========================================================
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

