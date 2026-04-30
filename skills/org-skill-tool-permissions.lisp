(in-package :opencortex)

(defvar *tool-permissions* (make-hash-table :test 'equal))

(defun set-tool-permission (tool-name level)
  "Sets the permission level for a tool."
  (setf (gethash (string-downcase (string tool-name)) *tool-permissions*) level))

(defun get-tool-permission (tool-name)
  "Retrieves the permission level for a tool."
  (gethash (string-downcase (string tool-name)) *tool-permissions* :ask))

(defskill :skill-tool-permissions
  :priority 600
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
