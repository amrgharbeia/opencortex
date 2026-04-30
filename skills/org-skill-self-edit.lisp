(in-package :opencortex)

(defun self-edit-apply (filepath old-text new-text)
  "Applies a transformation to a source file."
  (harness-log "SELF-EDIT: Applying changes to ~a" filepath))

(defskill :skill-self-edit
  :priority 100
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
