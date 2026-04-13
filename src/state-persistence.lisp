(in-package :org-agent)

(defun persistence-get-local-path ()
  "Returns the path to the local memory image file."
  (let ((state-dir (or (uiop:getenv "SYSTEM_DIR") "system/")))
    (merge-pathnames "state/memory-image.lisp" state-dir)))

(defun persistence-dump-local ()
  "Serializes the entire history store and current pointers to a local Lisp image."
  (let ((image-file (persistence-get-local-path)))
    (ensure-directories-exist image-file)
    (harness-log "PERSISTENCE - Dumping local image to ~a..." (uiop:native-namestring image-file))
    (with-open-file (out image-file :direction :output :if-exists :supersede)
      (format out "(in-package :org-agent)~%")
      ;; 1. Dump all immutable objects in the history store
      (maphash (lambda (hash obj)
                 (print `(setf (gethash ,hash *history-store*) ,obj) out))
               *history-store*)
      ;; 2. Dump the current active pointers
      (maphash (lambda (id obj)
                 (print `(setf (gethash ,id *memory*) (gethash ,(org-object-hash obj) *history-store*)) out))
               *memory*))
    t))

(defun persistence-load-local ()
  "Loads the memory image from local disk."
  (let ((image-file (persistence-get-local-path)))
    (if (uiop:file-exists-p image-file)
        (progn
          (harness-log "PERSISTENCE - Loading local image...")
          (load image-file)
          t)
        (progn
          (harness-log "PERSISTENCE ERROR - Local image not found.")
          nil))))

(defun persistence-serialize-for-archival ()
  "Serializes the entire object-store for IPFS/JSON transport."
  (let ((objects nil))
    (maphash (lambda (id obj)
               (declare (ignore id))
               (push `((:id . ,(org-object-id obj))
                       (:type . ,(format nil "~s" (org-object-type obj)))
                       (:attributes . ,(loop for (k v) on (org-object-attributes obj) by #'cddr 
                                             collect (cons (format nil "~a" k) (format nil "~a" v))))
                       (:content . ,(org-object-content obj))
                       (:parent-id . ,(org-object-parent-id obj))
                       (:children . ,(org-object-children obj))
                       (:version . ,(org-object-version obj))
                       (:last-sync . ,(org-object-last-sync obj))
                       (:hash . ,(org-object-hash obj)))
                     objects))
             *memory*)
    objects))

(defun persistence-push-ipfs ()
  "Serializes the store and pushes it to IPFS, returning the CID."
  (let* ((data (persistence-serialize-for-archival))
         (json-payload (cl-json:encode-json-to-string data))
         (ipfs-url "http://127.0.0.1:5001/api/v0/add"))
    (handler-case
        (let* ((response (dex:post ipfs-url 
                                   :content `(("file" . ,json-payload))
                                   :headers '(("Content-Type" . "multipart/form-data"))))
               (result (cl-json:decode-json-from-string response))
               (cid (cdr (assoc :hash result))))
          (harness-log "PERSISTENCE - Checkpoint to IPFS successful. CID: ~a" cid)
          cid)
      (error (c)
        (harness-log "PERSISTENCE ERROR - IPFS push failed: ~a" c)
        nil))))

(defun persistence-restore-ipfs (cid)
  "Fetches data from IPFS and safely hydrates the object-store."
  (let ((ipfs-url (format nil "http://127.0.0.1:5001/api/v0/cat?arg=~a" cid)))
    (handler-case
        (let* ((response (dex:post ipfs-url))
               (data (cl-json:decode-json-from-string response)))
          (clrhash *memory*)
          (dolist (item data)
            (let* ((id (cdr (assoc :id item)))
                   (obj (make-org-object 
                         :id id
                         :type (read-from-string (cdr (assoc :type item)))
                         :attributes (loop for attr in (cdr (assoc :attributes item))
                                           append (list (intern (string-upcase (car attr)) :keyword) (cdr attr)))
                         :content (cdr (assoc :content item))
                         :parent-id (cdr (assoc :parent-id item))
                         :children (cdr (assoc :children item))
                         :version (cdr (assoc :version item))
                         :last-sync (cdr (assoc :last-sync item))
                         :hash (cdr (assoc :hash item)))))
              (setf (gethash id *memory*) obj)))
          (harness-log "PERSISTENCE - Restored from IPFS: ~a" cid)
          t)
      (error (c)
        (harness-log "PERSISTENCE ERROR - IPFS restoration failed: ~a" c)
        nil))))

(progn
  (def-cognitive-tool :checkpoint-memory "Creates both a local image and a decentralized IPFS snapshot."
    :parameters nil
    :body (lambda (args)
            (declare (ignore args))
            (persistence-dump-local)
            (let ((cid (persistence-push-ipfs)))
              (format nil "Local dump complete. IPFS CID: ~a" (or cid "FAILED")))))

  (def-cognitive-tool :restore-memory "Restores the state from a specific source."
    :parameters ((:source :type :keyword :description "Either :LOCAL or :IPFS")
                 (:cid :type :string :description "Required if source is :IPFS"))
    :body (lambda (args)
            (case (getf args :source)
              (:local (if (persistence-load-local) "Restored from disk." "Local restore failed."))
              (:ipfs (if (persistence-restore-ipfs (getf args :cid)) "Restored from network." "IPFS restore failed."))))))

(defskill :skill-state-persistence
  :priority 100
  :trigger (lambda (ctx) 
             (let ((sensor (getf (getf ctx :payload) :sensor)))
               (member sensor '(:heartbeat :manual-persist))))
  :probabilistic nil
  :deterministic (lambda (action ctx)
              (persistence-dump-local)
              action))
