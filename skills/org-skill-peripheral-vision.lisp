(in-package :opencortex)

(defun peripheral-vision-summarize (obj-id)
  "Generates a low-resolution summary of an object."
  (let ((obj (lookup-object obj-id)))
    (if obj
        (format nil "Node: ~a (~a)" (getf (org-object-attributes obj) :TITLE) obj-id)
        "[Unknown Node]")))

(defskill :skill-peripheral-vision
  :priority 100
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
