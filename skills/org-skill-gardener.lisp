(in-package :opencortex)

(defvar *gardener-last-audit* 0
  "The universal-time of the last full Memex audit.")

(defun gardener-find-broken-links ()
  "Returns a list of broken ID links found in the Memex."
  (let ((broken nil))
    (maphash (lambda (id obj)
               (let ((content (org-object-content obj)))
                 (when content
                   (cl-ppcre:do-register-groups (target-id) ("id:([A-Za-z0-9-]+)" content)
                     (unless (lookup-object target-id)
                       (push (list :source id :broken-target target-id) broken))))))
             *memory*)
    broken))

(defun gardener-find-orphans ()
  "Returns a list of IDs for headlines that are structurally isolated."
  (let ((inbound (make-hash-table :test 'equal))
        (outbound (make-hash-table :test 'equal))
        (orphans nil))
    ;; 1. Map all connections
    (maphash (lambda (id obj)
               (let ((content (org-object-content obj)))
                 (when content
                   (cl-ppcre:do-register-groups (target-id) ("id:([A-Za-z0-9-]+)" content)
                     (setf (gethash id outbound) t)
                     (setf (gethash target-id inbound) t)))))
             *memory*)
    ;; 2. Identify nodes with zero connections
    (maphash (lambda (id obj)
               (declare (ignore obj))
               (unless (or (gethash id inbound) (gethash id outbound))
                 (push id orphans)))
             *memory*)
    orphans))

(defun gardener-deterministic-gate (action context)
  "Main gate for the Gardener skill. Audits graph integrity."
  (declare (ignore action context))
  (let ((broken (gardener-find-broken-links))
        (orphans (gardener-find-orphans)))
    
    (when (or broken orphans)
      (harness-log "GARDENER: Audit found ~a broken links and ~a orphans." 
                   (length broken) (length orphans))
      
      (dolist (link broken)
        (harness-log "  [BROKEN LINK] Node ~a -> ~a" (getf link :source) (getf link :broken-target)))
      
      (dolist (orphan orphans)
        (harness-log "  [ORPHAN] Node ~a is isolated." orphan)))
    
    (setf *gardener-last-audit* (get-universal-time))
    ;; Return a log to stop the loop
    (list :type :LOG :payload (list :text "Gardener audit complete."))))

(defskill :skill-gardener
  :priority 40
  :trigger (lambda (ctx)
             (let* ((payload (getf ctx :payload))
                    (sensor (getf payload :sensor)))
               (and (eq sensor :heartbeat)
                    ;; Only audit once per day
                    (> (- (get-universal-time) *gardener-last-audit*) 86400))))
  :probabilistic nil
  :deterministic #'gardener-deterministic-gate)
