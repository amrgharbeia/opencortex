(in-package :org-agent)

(defun set-llm-model (provider model-id)
  "Registers a preferred model for a provider in the Memory."
  (let ((config-id (format nil "config-llm-~a" (string-downcase (string provider)))))
    (let ((obj (make-org-object 
                :id config-id
                :type :CONFIG
                :attributes `(:provider ,provider :model-id ,model-id)
                :content (format nil "Fleet preference for ~a set to ~a" provider model-id)
                :version (get-universal-time))))
      (setf (gethash config-id *memory*) obj)
      (harness-log "CONFIG - Fleet updated: ~a -> ~a" provider model-id)
      t)))

(defun get-llm-model (provider &optional default)
  "Retrieves the preferred model for a provider from the Memory."
  (let* ((config-id (format nil "config-llm-~a" (string-downcase (string provider))))
         (obj (gethash config-id *memory*)))
    (if obj
        (getf (org-object-attributes obj) :model-id)
        default)))
