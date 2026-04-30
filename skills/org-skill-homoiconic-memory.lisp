(in-package :opencortex)

(defun memory-self-inspect ()
  "Allows the system to inspect its own memory state."
  (harness-log "MEMORY: Self-inspection triggered."))

(defskill :skill-homoiconic-memory
  :priority 100
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
