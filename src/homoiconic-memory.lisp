(in-package :org-agent)

(defun make-memory-node (headline &key content properties children)
  "Constructor for a normalized Org node alist."
  (list :type :HEADLINE
        :properties (or properties nil)
        :content content
        :contents children))

(defun org-id-get-create ()
  "Generates a new unique ID for an Org node. This is the system-wide standard."
  (format nil "node-~a" (get-universal-time)))

(defun memory-ensure-id (node)
  "Injects a unique ID into an Org node if missing, using the standard org-id-get-create mechanism."
  (let* ((props (getf node :properties))
         (id (getf props :ID)))
    (if (and id (not (equal id "")))
        node
        (let ((new-id (org-agent:org-id-get-create)))
          (setf (getf node :properties) (append props (list :ID new-id)))
          (harness-log "MEMORY - Injected standard ID ~a" new-id)
          node))))

(defun memory-normalize-ast (ast)
  "Recursively normalizes an Org AST."
  (let ((type (getf ast :type))
        (contents (getf ast :contents)))
    (when (eq type :HEADLINE)
      (setf ast (memory-ensure-id ast)))
    (when contents
      (setf (getf ast :contents)
            (mapcar (lambda (child)
                      (if (listp child)
                          (memory-normalize-ast child)
                          child))
                    contents)))
    ast))

(defun memory-org-to-json (source-path)
  "Routes to the Emacs-based Org-JSON bridge."
  ;; Future implementation will use the org-json-convert CLI tool
  (harness-log "MEMORY - Parsing ~a to JSON..." source-path)
  nil)

(defun memory-json-to-org (ast)
  "Materializes a JSON AST into Org-mode text."
  ;; Placeholder for org-element-interpret-data equivalent
  (harness-log "MEMORY - Rendering AST to text...")
  "")

(progn
  (defskill :skill-homoiconic-memory
    :priority 300 ; Core foundational skill
    :trigger (lambda (ctx) (member (getf (getf ctx :payload) :sensor) '(:buffer-save :ingest)))
    :neuro nil
    :symbolic (lambda (action ctx)
                (let ((ast (getf (getf ctx :payload) :ast)))
                  (when ast (memory-normalize-ast ast))
                  action))))
