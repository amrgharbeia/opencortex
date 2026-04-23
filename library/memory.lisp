(in-package :opencortex)

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

(defvar *memory-snapshot-path* nil
  "Path to the memory snapshot file. Set from MEMORY_SNAPSHOT_PATH env or default.")

(defun ensure-memory-snapshot-path ()
  "Initializes the snapshot path from environment or default location."
  (or *memory-snapshot-path*
      (let ((env-path (uiop:getenv "MEMORY_SNAPSHOT_PATH")))
        (setf *memory-snapshot-path*
              (or env-path
                  (uiop:merge-pathnames* "memory.snap" (user-homedir-pathname)))))))

(defun save-memory-to-disk ()
  "Serializes *memory* and *history-store* to disk for crash recovery.
Converts hash tables to alists for proper serialization."
  (let ((path (ensure-memory-snapshot-path)))
    (with-open-file (stream path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format stream ";; OpenCortex Memory Snapshot~%")
      (format stream ";; Created: ~a~%~%" (format nil "~a" (get-universal-time)))
      (let ((memory-alist nil)
            (history-alist nil))
        (maphash (lambda (k v) (push (cons k v) memory-alist)) *memory*)
        (maphash (lambda (k v) (push (cons k v) history-alist)) *history-store*)
        (prin1 (list :memory memory-alist :history-store history-alist) stream)))
    (harness-log "MEMORY - Saved to ~a" path)
    path))

(defun load-memory-from-disk ()
  "Loads *memory* and *history-store* from disk if the snapshot exists.
Reconstitutes alists into hash tables."
  (let ((path (ensure-memory-snapshot-path)))
    (when (uiop:file-exists-p path)
      (handler-case
          (with-open-file (stream path :direction :input)
            (let ((data (read stream nil)))
              (when data
                (let ((memory-alist (getf data :memory))
                      (history-alist (getf data :history-store)))
                  (setf *memory* (make-hash-table :test 'equal :size (length memory-alist)))
                  (dolist (kv memory-alist)
                    (setf (gethash (car kv) *memory*) (cdr kv)))
                  (setf *history-store* (make-hash-table :test 'equal :size (length history-alist)))
                  (dolist (kv history-alist)
                    (setf (gethash (car kv) *history-store*) (cdr kv)))
                  (harness-log "MEMORY - Loaded from ~a (~a objects)" path (hash-table-size *memory*))))))
          (error (c)
            (harness-log "MEMORY WARNING - Failed to load snapshot: ~a" c))))
    t))

(defun org-id-new ()
  "Generates a new UUID string for Org-mode identification."
  (string-downcase (format nil "~a" (uuid:make-v4-uuid))))

(defun lookup-object (id) 
  "Retrieves an object from the store by its unique ID."
  (gethash id *memory*))

(defun list-objects-by-type (type)
  "Returns a list of all objects matching a specific Org element type."
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (eq (org-object-type obj) type) (push obj results))) *memory*)
    results))
(defun list-objects-with-attribute (attr-name value)
  "Returns a list of all objects where ATTR-NAME matches VALUE."
  (let ((results nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (let ((attrs (org-object-attributes obj)))
                 (when (equal (getf attrs attr-name) value)
                   (push obj results))))
             *memory*)
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

(defvar *embedding-cache* (make-hash-table :test 'equal)
  "Cache for embeddings to avoid redundant API calls.")

(defun get-embedding (text)
  "Generates a vector embedding for the given text via Ollama. Returns nil on failure."
  (when (or (null text) (string= text ""))
    (return-from get-embedding nil))
  (let ((cached (gethash text *embedding-cache*)))
    (when cached (return-from get-embedding cached)))
  (let ((result (funcall (get-cognitive-tool-body :get-ollama-embedding) (list :text text))))
    (when (eq (getf result :status) :success)
      (let ((vec (getf result :vector)))
        (setf (gethash text *embedding-cache*) vec)
        vec))))

(defun cosine-similarity (vec-a vec-b)
  "Computes cosine similarity between two vectors. Both should be sequences of numbers."
  (when (or (null vec-a) (null vec-b) (zerop (length vec-a)) (zerop (length vec-b)))
    (return-from cosine-similarity 0.0))
  (let ((dot-product (loop for a across vec-a
                          for b across vec-b
                          sum (* a b)))
        (norm-a (sqrt (loop for a across vec-a sum (* a a))))
        (norm-b (sqrt (loop for b across vec-b sum (* b b)))))
    (if (or (zerop norm-a) (zerop norm-b))
        0.0
        (/ dot-product (* norm-a norm-b)))))

(defun semantic-search (query &key (limit 10) (min-similarity 0.5))
  "Searches memory for objects semantically similar to the query."
  (let* ((query-vec (get-embedding query))
         (results nil))
    (unless query-vec
      (harness-log "EMBEDDING: Failed to generate embedding for query: ~a" query)
      (return-from semantic-search nil))
    (maphash (lambda (id obj)
               (let ((obj-vec (org-object-vector obj)))
                 (when obj-vec
                   (let ((sim (cosine-similarity query-vec obj-vec)))
                     (when (>= sim min-similarity)
                       (push (list :id id :object obj :similarity sim) results))))))
             *memory*)
    (setf results (sort results #'> :key (lambda (r) (getf r :similarity))))
    (subseq results 0 (min limit (length results)))))

(def-cognitive-tool :semantic-search
  "Searches memory for objects semantically similar to a query."
  ((:query :type :string :description "The search query.")
   (:limit :type :integer :description "Maximum results to return." :default 10)
   (:min-similarity :type :number :description "Minimum similarity threshold (0-1)." :default 0.5))
  :body (lambda (args)
          (semantic-search (getf args :query)
                        :limit (or (getf args :limit) 10)
                        :min-similarity (or (getf args :min-similarity) 0.5))))
