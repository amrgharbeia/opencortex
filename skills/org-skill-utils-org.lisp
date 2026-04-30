(in-package :opencortex)

(defun utils-org-read-file (filepath)
  "Reads an Org file into a string."
  (uiop:read-file-string filepath))

(defun utils-org-write-file (filepath content)
  "Writes content to an Org file."
  (uiop:with-output-file (s filepath :if-exists :supersede)
    (format s "~a" content)))

(defun utils-org-generate-id ()
  "Generates a new UUID for an Org node."
  (string-downcase (format nil "~a" (uuid:make-v4-uuid))))

(defun utils-org-id-format (id)
  "Ensures the ID has the 'id:' prefix."
  (if (uiop:string-prefix-p "id:" id)
      id
      (format nil "id:~a" id)))

(defun utils-org-set-property (ast target-id property value)
  "Recursively sets a property on a headline with a matching ID in the AST."
  (let ((type (getf ast :type))
        (props (getf ast :properties))
        (contents (getf ast :contents)))
    (when (and (eq type :HEADLINE) (string= (getf props :ID) target-id))
      (setf (getf (getf ast :properties) property) value)
      (return-from utils-org-set-property t))
    (dolist (child contents)
      (when (listp child)
        (when (utils-org-set-property child target-id property value)
          (return-from utils-org-set-property t)))))
  nil)

(defun utils-org-set-todo (ast target-id status)
  "Sets the TODO status of a headline in the AST."
  (utils-org-set-property ast target-id :TODO status))

(defun utils-org-add-headline (ast parent-id title)
  "Adds a new headline as a child of the parent-id in the AST."
  (let ((type (getf ast :type))
        (props (getf ast :properties))
        (id (getf props :ID))
        (contents (getf ast :contents)))
    (when (and (eq type :HEADLINE) (string= id parent-id))
      (let ((new-node (list :type :HEADLINE
                           :properties (list :ID (utils-org-id-format (utils-org-generate-id))
                                            :TITLE title)
                           :contents nil)))
        (setf (getf ast :contents) (append contents (list new-node)))
        (return-from utils-org-add-headline t)))
    (dolist (child contents)
      (when (listp child)
        (when (utils-org-add-headline child parent-id title)
          (return-from utils-org-add-headline t)))))
  nil)

(defun utils-org-find-headline-by-id (ast id)
  "Finds a headline by its ID in the AST."
  (let ((props (getf ast :properties)))
    (when (string= (getf props :ID) id)
      (return-from utils-org-find-headline-by-id ast))
    (dolist (child (getf ast :contents))
      (when (listp child)
        (let ((found (utils-org-find-headline-by-id child id)))
          (when found (return-from utils-org-find-headline-by-id found)))))
    nil))

(defun utils-org-find-headline-by-title (ast title)
  "Finds a headline by its title in the AST."
  (let ((props (getf ast :properties)))
    (when (string-equal (getf props :TITLE) title)
      (return-from utils-org-find-headline-by-title ast))
    (dolist (child (getf ast :contents))
      (when (listp child)
        (let ((found (utils-org-find-headline-by-title child title)))
          (when found (return-from utils-org-find-headline-by-title found)))))
    nil))

(defun utils-org-modify (filepath id changes)
  "Placeholder for Emacs-driven modification of a specific node."
  (harness-log "UTILS-ORG: Applying changes to ~a in ~a" id filepath)
  (declare (ignore changes))
  t)

(defun utils-org-ast-to-org (ast)
  "Minimal converter from AST back to Org text (Placeholder)."
  (declare (ignore ast))
  "* TITLE (Placeholder)")

(defskill :skill-utils-org
  :priority 100
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
