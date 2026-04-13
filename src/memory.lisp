(in-package :org-agent)

(defvar *memory* (make-hash-table :test 'equal))

(defvar *history-store* (make-hash-table :test 'equal)
  "Immutable Merkle-Tree versioning store mapping hashes to objects.")

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
  "Parses an Org AST into the recursive Lisp Memory with Merkle hashing."
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
          (let ((child-id-val child-id))
             (let ((child-obj (lookup-object child-id-val)))
               (when child-obj (push (org-object-hash child-obj) child-hashes)))))))
    (setf child-ids (nreverse child-ids))
    (setf child-hashes (nreverse child-hashes))
    (let* ((hash (compute-merkle-hash id type props raw-content child-hashes))
           (existing-obj (gethash hash *history-store*))
           (obj (or existing-obj
                    (make-org-object 
                     :id id :type type :attributes props :content raw-content
                     :vector (when should-embed (get-embedding raw-content))
                     :parent-id parent-id :children child-ids
                     :version (get-universal-time) :last-sync (get-universal-time)
                     :hash hash))))
      (unless existing-obj
        (setf (gethash hash *history-store*) obj))
      (setf (gethash id *memory*) obj)
      id)))

(defvar *object-store-snapshots* nil)

(defun copy-hash-table (hash-table)
  "Creates a shallow copy of a hash table."
  (let ((new-table (make-hash-table :test (hash-table-test hash-table) 
                                    :size (hash-table-size hash-table))))
    (maphash (lambda (k v) (setf (gethash k new-table) v)) hash-table)
    new-table))

(defun snapshot-memory ()
  "Creates a lightweight, Copy-on-Write snapshot using Merkle-Tree pointers."
  (let ((snapshot (copy-hash-table *memory*)))
    (push (list :timestamp (get-universal-time) :data snapshot) *object-store-snapshots*)
    (when (> (length *object-store-snapshots*) 20)
      (setf *object-store-snapshots* (subseq *object-store-snapshots* 0 20)))
    (harness-log "MEMORY - CoW Memory snapshot created.")))

(defun rollback-memory (&optional (index 0))
  "Restores the Memory to a previously captured snapshot using immutable history pointers."
  (let ((snapshot (nth index *object-store-snapshots*)))
    (if snapshot
        (progn (setf *memory* (copy-hash-table (getf snapshot :data)))
               (harness-log "MEMORY - Memory rolled back to snapshot ~a" index))
        (harness-log "MEMORY ERROR - Snapshot ~a not found." index))))

(defun lookup-object (id) 
  "Retrieves an object from the store by its unique ID."
  (gethash id *memory*))

(defun list-objects-by-type (type)
  "Returns a list of all objects matching a specific Org element type."
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (eq (org-object-type obj) type) (push obj results))) *memory*)
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
