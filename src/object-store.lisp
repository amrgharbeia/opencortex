(in-package :org-agent)

(defvar *object-store* (make-hash-table :test 'equal))

(defstruct org-object
  id type attributes content vector parent-id children version last-sync)

(defun ingest-ast (ast &optional parent-id)
  (let* ((type (getf ast :type))
         (props (getf ast :properties))
         (id (or (getf props :ID) (format nil "temp-~a" (get-universal-time))))
         (contents (getf ast :contents))
         (raw-content (when (eq type :HEADLINE)
                        (format nil "~a~%~a" (getf props :TITLE) (or (cl:getf ast :raw-content) ""))))
         (should-embed (and raw-content (equal (getf props :EMBED) "t")))
         (child-ids nil))
    (dolist (child contents)
      (when (listp child) (push (ingest-ast child id) child-ids)))
    (let ((obj (make-org-object 
                :id id :type type :attributes props :content raw-content
                :vector (when should-embed (get-embedding raw-content))
                :parent-id parent-id :children (nreverse child-ids)
                :version (get-universal-time) :last-sync (get-universal-time))))
      (setf (gethash id *object-store*) obj)
      id)))

(defvar *object-store-snapshots* nil)

(defun clone-org-object (obj)
  (make-org-object 
   :id (org-object-id obj) :type (org-object-type obj)
   :attributes (copy-list (org-object-attributes obj))
   :content (org-object-content obj) :vector (org-object-vector obj)
   :parent-id (org-object-parent-id obj) :children (copy-list (org-object-children obj))
   :version (org-object-version obj) :last-sync (org-object-last-sync obj)))

(defun snapshot-object-store ()
  (let ((snapshot (make-hash-table :test 'equal)))
    (maphash (lambda (id obj) (setf (gethash id snapshot) (clone-org-object obj))) *object-store*)
    (push (list :timestamp (get-universal-time) :data snapshot) *object-store-snapshots*)
    (when (> (length *object-store-snapshots*) 20)
      (setf *object-store-snapshots* (subseq *object-store-snapshots* 0 20)))
    (kernel-log "MEMORY - Object Store snapshot created.")))

(defun rollback-object-store (&optional (index 0))
  (let ((snapshot (nth index *object-store-snapshots*)))
    (if snapshot
        (progn (setf *object-store* (getf snapshot :data))
               (kernel-log "MEMORY - Object Store rolled back to snapshot ~a" index))
        (kernel-log "MEMORY ERROR - Snapshot ~a not found." index))))

(defun lookup-object (id) (gethash id *object-store*))

(defun list-objects-by-type (type)
  (let ((results nil))
    (maphash (lambda (id obj) (declare (ignore id)) (when (eq (org-object-type obj) type) (push obj results))) *object-store*)
    results))

(defun find-headline-missing-id (ast)
  (when (listp ast)
    (if (and (eq (getf ast :type) :HEADLINE) (not (getf (getf ast :properties) :ID)))
        ast
        (cl:some #'find-headline-missing-id (getf ast :contents)))))

(defun file-name-nondirectory (path)
  (let ((pos (position #\/ path :from-end t))) (if pos (subseq path (1+ pos)) path)))
