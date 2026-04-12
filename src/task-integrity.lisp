(in-package :org-agent)

(defun semantic-mapping (task-state)
  "Maps Org-mode task states to semantic categories."
  (case (intern (string-upcase task-state) :keyword)
    ((:todo :active :started :wait) :active)
    ((:done :cancelled :resolved) :resolved)
    (t :unknown)))

(defun detect-active-children (task-id)
  "Checks if a task has any child tasks in an active state."
  (let ((children (list-objects-with-attribute :PARENT task-id)))
    (remove-if-not (lambda (child)
                     (let ((todo (getf (org-object-attributes child) :TODO)))
                       (and todo (eq (semantic-mapping todo) :active))))
                   children)))
