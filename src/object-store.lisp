(in-package :org-agent)

(defvar *object-store* (make-hash-table :test 'equal))

(defstruct org-object
  id type attributes content vector parent-id children version last-sync hash)

(defun compute-merkle-hash (id type attributes content child-hashes)
  "Computes a SHA-256 Merkle hash for a node based on its core properties and children's hashes."
  (let* ((alist (loop for (k v) on attributes by #'cddr collect (cons k v)))
         (sorted-alist (sort alist #'string< :key (lambda (x) (format nil "~a" (car x)))))
         (attr-string (format nil "~s" sorted-alist))
         (children-string (format nil "~{~a~}" child-hashes))
         (data-string (format nil "ID:~a|TYPE:~s|ATTRS:~a|CONTENT:~a|CHILDREN:~a"
                              id type attr-string (or content "") children-string))
         (digester (ironclad:make-digest :sha256)))
    (ironclad:update-digest digester (ironclad:ascii-string-to-byte-array data-string))
    (ironclad:byte-array-to-hex-string (ironclad:produce-digest digester))))

(defun ingest-ast (ast &optional parent-id)
  "Parses an Org AST into the recursive Lisp Object Store with Merkle hashing."
  (let* ((type (getf ast :type))
         (props (getf ast :properties))
         (id (or (getf props :ID) (format nil "temp-~a" (get-universal-time))))
         (contents (getf ast :contents))
         (raw-content (when (eq type :HEADLINE)
                        (format nil "~a~%~a" (getf props :TITLE) (or (cl:getf ast :raw-content) ""))))
         (should-embed (and raw-content (equal (getf props :EMBED) "t")))
         (child-ids nil)
         (child-hashes nil))
    (dolist (child contents)
      (when (listp child)
        (let ((child-id (ingest-ast child id)))
          (push child-id child-ids)
          (let ((child-obj (lookup-object child-id)))
            (when child-obj (push (org-object-hash child-obj) child-hashes))))))
    (setf child-ids (nreverse child-ids))
    (setf child-hashes (nreverse child-hashes))
    (let* ((hash (compute-merkle-hash id type props raw-content child-hashes))
           (obj (make-org-object 
                 :id id :type type :attributes props :content raw-content
                 :vector (when should-embed (get-embedding raw-content))
                 :parent-id parent-id :children child-ids
                 :version (get-universal-time) :last-sync (get-universal-time)
                 :hash hash)))
      (setf (gethash id *object-store*) obj)
      id)))

(defvar *object-store-snapshots* nil)

(defun clone-org-object (obj)
  "Creates a deep copy of an org-object structure."
  (make-org-object 
   :id (org-object-id obj) :type (org-object-type obj)
   :attributes (copy-list (org-object-attributes obj))
   :content (org-object-content obj) :vector (org-object-vector obj)
   :parent-id (org-object-parent-id obj) :children (copy-list (org-object-children obj))
   :version (org-object-version obj) :last-sync (org-object-last-sync obj)
   :hash (org-object-hash obj)))

(defun snapshot-object-store ()
  "Creates an immutable point-in-time image of the current knowledge graph."
  (let ((snapshot (make-hash-table :test 'equal)))
    (maphash (lambda (id obj) (setf (gethash id snapshot) (clone-org-object obj))) *object-store*)
    (push (list :timestamp (get-universal-time) :data snapshot) *object-store-snapshots*)
    (when (> (length *object-store-snapshots*) 20)
      (setf *object-store-snapshots* (subseq *object-store-snapshots* 0 20)))
    (kernel-log "MEMORY - Object Store snapshot created.")))

(defun rollback-object-store (&optional (index 0))
  "Restores the Object Store to a previously captured snapshot."
  (let ((snapshot (nth index *object-store-snapshots*)))
    (if snapshot
        (progn (setf *object-store* (getf snapshot :data))
               (kernel-log "MEMORY - Object Store rolled back to snapshot ~a" index))
        (kernel-log "MEMORY ERROR - Snapshot ~a not found." index))))

(defun lookup-object (id) (gethash id *object-store*))
  "Retrieves an object from the store by its unique ID."
  (defun list-objects-by-type (type)
  "Returns a list of all objects matching a specific Org element type."
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (eq (org-object-type obj) type) (push obj results))) *object-store*)
    results))

(defun find-headline-missing-id (ast)
  "Traverses an AST to find headlines that lack an :ID: property."
  (when (listp ast)
    (if (and (eq (getf ast :type) :HEADLINE) (not (getf (getf ast :properties) :ID)))
        ast
        (cl:some #'find-headline-missing-id (getf ast :contents)))))

(defun file-name-nondirectory (path)
  "Extracts the filename from a full path string."
  (let ((pos (position #\/ path :from-end t))) (if pos (subseq path (1+ pos)) path)))
