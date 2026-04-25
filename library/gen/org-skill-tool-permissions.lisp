(in-package :opencortex)

(defvar *tool-permissions* (make-hash-table :test 'equal)
  "Hash table mapping tool names to :allow/:deny/:ask.")

(defun get-tool-permission (tool-name)
  (let ((key (string-downcase (string tool-name))))
    (or (gethash key *tool-permissions*) :allow)))

(defun set-tool-permission (tool-name tier)
  (setf (gethash (string-downcase (string tool-name)) *tool-permissions*) tier)
  (harness-log "TOOL PERMISSION: Set ~a = ~a" tool-name tier))

(defun check-tool-permission-gate (tool-name context)
  (declare (ignore context))
  (let ((perm (get-tool-permission tool-name)))
    (case perm
      (:allow :allow)
      (:deny :deny)
      (:ask (list :ask tool-name context))
      (t :allow))))

(def-cognitive-tool :get-embedding
  "Generates vector embeddings via Ollama or llama.cpp API."
  ((:text :type :string :description "Text to embed."))
  :body (lambda (args)
          (let* ((text (getf args :text))
                 (provider (or (uiop:getenv "EMBEDDING_PROVIDER") "ollama"))
                 (model (or (uiop:getenv "EMBEDDING_MODEL") "nomic-embed-text"))
                 (embedding nil))
            (cond
              ((string= provider "ollama")
               (let* ((host (or (uiop:getenv "OLLAMA_HOST") "localhost:11434"))
                      (url (format nil "http://~a/api/embeddings" host))
                      (body (cl-json:encode-json-to-string `((model . ,model) (prompt . ,text)))))
                 (handler-case
                     (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body :connect-timeout 5 :read-timeout 30))
                            (json (cl-json:decode-json-from-string response))
                            (vec (cdr (assoc :embedding json))))
                       (when vec (setf embedding vec)))
                   (error (c) (harness-log "EMBEDDING: Ollama failed: ~a" c)))))
              ((string= provider "llama.cpp")
               (let* ((host (or (uiop:getenv "LLAMA_HOST") "localhost:8080"))
                      (url (format nil "http://~a/v1/embeddings" host))
                      (body (cl-json:encode-json-to-string `((model . ,model) (input . ,text)))))
                 (handler-case
                     (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body :connect-timeout 5 :read-timeout 30))
                            (json (cl-json:decode-json-from-string response))
                            (data (cdr (assoc :data json)))
                            (vec (when data (cdr (assoc :embedding (car data))))))
                       (when vec (setf embedding vec)))
                   (error (c) (harness-log "EMBEDDING: llama.cpp failed: ~a" c))))))
            (if embedding
                (list :status :success :vector embedding)
                (list :status :error :message "Embedding generation failed")))))

(def-cognitive-tool :tool-permissions
  "View or set tool permission tiers."
  ((:tool :type :string :description "Tool name")
   (:action :type :keyword :description "Action: :get, :set, :list" :default :get)
   (:tier :type :keyword :description "For :set: :allow/:deny/:ask"))
  :body (lambda (args)
          (let ((tool (getf args :tool))
                (action (getf args :action :get))
                (tier (getf args :tier)))
            (case action
              (:get (list :status :success :tool tool :permission (get-tool-permission tool)))
              (:set (progn (set-tool-permission tool tier)
                        (list :status :success :message (format nil "Set ~a = ~a" tool tier))))
              (:list (let ((r nil))
                       (maphash (lambda (k v) (push (list :tool k :permission v) r)) *tool-permissions*)
                       (list :status :success :tools r)))
              (t (list :status :error :message "Invalid action"))))))

;; Defaults
(set-tool-permission :shell :deny)
(set-tool-permission :delete-file :deny)
(set-tool-permission :eval :ask)
(set-tool-permission :write-file :ask)
(harness-log "TOOL PERMISSIONS: Initialized")

(defskill :skill-tool-permissions
  :priority 600
  :trigger (lambda (c) (declare (ignore c)) nil)
  :deterministic (lambda (a c)
    (let ((tool (getf (getf a :payload) :tool)))
      (when tool (check-tool-permission-gate tool c)))))
