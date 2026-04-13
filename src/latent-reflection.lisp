(in-package :org-agent)

(defvar *last-reflection-time* 0)
(defvar *reflection-interval* 14400) ;; 4 hours by default

(defun sample-random-memories (count)
  "Returns COUNT random objects from the object-store."
  (let ((keys nil)
        (selected nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k keys)) *memory*)
    (let ((len (length keys)))
      (when (> len 0)
        (dotimes (i count)
          (let* ((random-key (nth (random len) keys))
                 (obj (gethash random-key *memory*)))
            (when obj
              (push obj selected))))))
    selected))

(def-cognitive-tool :trigger-latent-reflection "Manually triggers a proactive gardening cycle."
  :parameters nil
  :body (lambda (args)
          (declare (ignore args))
          (setf *last-reflection-time* 0)
          "Latent reflection triggered. Wait for the next heartbeat."))

(defskill :skill-latent-reflection
  :priority 30
  :trigger (lambda (ctx) 
             (let* ((payload (getf ctx :payload))
                    (sensor (getf payload :sensor))
                    (now (get-universal-time)))
               (if (and (eq sensor :heartbeat)
                        (> (- now *last-reflection-time*) *reflection-interval*))
                   (progn
                     (harness-log "GARDENER - Initiating Latent Reflection...")
                     (setf *last-reflection-time* now)
                     t)
                   nil)))
  :probabilistic (lambda (ctx)
           (declare (ignore ctx))
           (let* ((memories (sample-random-memories 3))
                  (context-string "LATENT REFLECTION CANDIDATES:\n"))
             (dolist (m memories)
               (let ((title (or (getf (org-object-attributes m) :TITLE) "Untitled"))
                     (content (or (org-object-content m) "")))
                 (setf context-string 
                       (concatenate 'string context-string 
                                    (format nil "- ID: ~a | TITLE: ~a | CONTENT: ~a~%" 
                                            (org-object-id m) title content)))))
             (format nil "You are the Proactive Gardener of the Memex. 
I have selected 3 random notes from the knowledge graph. 
Please read them and synthesize a 'Latent Reflection'. 
Find hidden connections, suggest new tags, or propose a new insight that bridges them.

~a

MANDATE: Output EXACTLY ONE Common Lisp property list starting with (:type :REQUEST).
Use the :emacs target and :insert-at-end action to write your reflection into the \"*org-agent-chat*\" buffer." 
                     context-string)))
  :deterministic (lambda (action ctx) 
              (declare (ignore ctx))
              ;; Approve any safe request
              action))
