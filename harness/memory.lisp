(in-package :opencortex)

(defvar *memory* (make-hash-table :test 'equal))
(defvar *history-store* (make-hash-table :test 'equal)
  "Immutable Merkle-Tree versioning store mapping hashes to objects.")

(defstruct org-object
  id type attributes content vector parent-id children version last-sync hash)

(defmethod make-load-form ((obj org-object) &optional env)
  (make-load-form-saving-slots obj :environment env))

(defun copy-org-object (obj)
  (make-org-object :id (org-object-id obj)
                  :type (org-object-type obj)
                  :attributes (copy-list (org-object-attributes obj))
                  :content (org-object-content obj)
                  :vector (org-object-vector obj)
                  :parent-id (org-object-parent-id obj)
                  :children (copy-list (org-object-children obj))
                  :version (org-object-version obj)
                  :last-sync (org-object-last-sync obj)
                  :hash (org-object-hash obj)))

(defun compute-merkle-hash (id type attributes content child-hashes)
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
  (let* ((type (getf ast :type))
         (props (getf ast :properties))
         (id (or (getf props :ID) (format nil "temp-~a" (get-universal-time))))
         (contents (getf ast :contents))
         (raw-content (when (eq type :HEADLINE)
                        (format nil "~a~%~a" (getf props :TITLE) (or (getf ast :raw-content) ""))))
         (child-ids nil) (child-hashes nil))
    (dolist (child contents)
      (when (listp child)
        (let ((child-id (ingest-ast child id)))
          (push child-id child-ids)
          (let ((child-obj (gethash child-id *memory*)))
            (when child-obj (push (org-object-hash child-obj) child-hashes))))))
    (setf child-ids (nreverse child-ids))
    (setf child-hashes (nreverse child-hashes))
    (let* ((hash (compute-merkle-hash id type props raw-content child-hashes))
           (existing-obj (gethash hash *history-store*))
           (obj (or existing-obj
                    (make-org-object 
                     :id id :type type :attributes props :content raw-content
                     :parent-id parent-id :children child-ids
                     :version (get-universal-time) :last-sync (get-universal-time)
                     :hash hash))))
      (unless existing-obj (setf (gethash hash *history-store*) obj))
      (setf (gethash id *memory*) obj)
      id)))

(defvar *object-store-snapshots* nil)

(defun copy-hash-table (hash-table)
  (let ((new-table (make-hash-table :test (hash-table-test hash-table) 
                                    :size (hash-table-size hash-table))))
    (maphash (lambda (k v) (setf (gethash k new-table) v)) hash-table)
    new-table))

(defun snapshot-memory ()
  (let ((snapshot (make-hash-table :test 'equal :size (hash-table-size *memory*))))
    (maphash (lambda (k v) (setf (gethash k snapshot) (copy-org-object v))) *memory*)
    (push (list :timestamp (get-universal-time) :data snapshot) *object-store-snapshots*)
    (when (> (length *object-store-snapshots*) 20) (setf *object-store-snapshots* (subseq *object-store-snapshots* 0 20)))
    (harness-log "MEMORY - CoW Memory snapshot created.")))

(defun rollback-memory (&optional (index 0))
  (let ((snapshot (nth index *object-store-snapshots*)))
    (if snapshot
        (progn (setf *memory* (copy-hash-table (getf snapshot :data)))
               (harness-log "MEMORY - Memory rolled back to snapshot ~a" index))
        (harness-log "MEMORY ERROR - Snapshot ~a not found." index))))

(defvar *memory-snapshot-path* nil)

(defun ensure-memory-snapshot-path ()
  (or *memory-snapshot-path*
      (let ((env-path (uiop:getenv "MEMORY_SNAPSHOT_PATH")))
        (setf *memory-snapshot-path*
              (or env-path (namestring (uiop:merge-pathnames* "memory.snap" (user-homedir-pathname))))))))

(defun save-memory-to-disk ()
  (let ((path (ensure-memory-snapshot-path)))
    (with-open-file (stream path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (let ((memory-alist nil) (history-alist nil))
        (maphash (lambda (k v) (push (cons k v) memory-alist)) *memory*)
        (maphash (lambda (k v) (push (cons k v) history-alist)) *history-store*)
        (prin1 (list :memory memory-alist :history-store history-alist) stream)))
    (harness-log "MEMORY - Saved to ~a" path)))

(defun load-memory-from-disk ()
  (let ((path (ensure-memory-snapshot-path)))
    (when (uiop:file-exists-p path)
      (handler-case
          (with-open-file (stream path :direction :input)
            (let ((data (read stream nil)))
              (when data
                (let ((memory-alist (getf data :memory)) (history-alist (getf data :history-store)))
                  (setf *memory* (make-hash-table :test 'equal :size (length memory-alist)))
                  (dolist (kv memory-alist) (setf (gethash (car kv) *memory*) (cdr kv)))
                  (setf *history-store* (make-hash-table :test 'equal :size (length history-alist)))
                  (dolist (kv history-alist) (setf (gethash (car kv) *history-store*) (cdr kv)))
                  (harness-log "MEMORY - Loaded from ~a (~a objects)" path (hash-table-size *memory*))))))
          (error (c) (harness-log "MEMORY WARNING - Failed to load snapshot: ~a" c)))))
  t)
