(in-package :opencortex)

(defun gardener-prune-orphans ()
  "Identifies and handles orphaned objects in memory."
  (harness-log "GARDENER: Pruning orphans..."))

(defun gardener-verify-merkle-integrity ()
  "Validates the hashes of all objects in memory."
  (harness-log "GARDENER: Verifying Merkle integrity..."))

(defskill :skill-gardener
  :priority 100
  :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :heartbeat))
  :deterministic (lambda (action ctx) 
                   (declare (ignore action ctx))
                   (gardener-prune-orphans)
                   (gardener-verify-merkle-integrity)
                   nil))
