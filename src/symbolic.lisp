(in-package :org-agent)

(defun decide (proposed-action context)
  "The Deliberate Safety Gate: iterates through all skill symbolic-gates sorted by priority."
  (let ((current-action proposed-action)
        (skills nil))
    ;; 1. Collect all skills with symbolic gates
    (maphash (lambda (name skill)
               (declare (ignore name))
               (when (skill-symbolic-fn skill)
                 (push skill skills)))
             *skills-registry*)
    
    ;; 2. Sort skills by priority (highest first)
    (setf skills (sort skills #'> :key #'skill-priority))
    
    ;; 3. Execute symbolic gates sequentially
    (dolist (skill skills)
      (let ((gate (skill-symbolic-fn skill)))
        (setf current-action (funcall gate current-action context))
        ;; If any gate returns a LOG or EVENT (blocking/intercepting), stop and return it.
        (when (and (listp current-action) 
                   (member (getf current-action :type) '(:LOG :EVENT :log :event)))
          (harness-log "DELIBERATE: Intercepted by skill '~a'~%" (skill-name skill))
          (return-from decide current-action))))
    
    current-action))

(defun list-objects-with-attribute (attr-key attr-val)
  "Filters the Object Store for nodes having a specific attribute value."
  (let ((results nil))
    (maphash (lambda (id obj) 
               (declare (ignore id)) 
               (when (equal (getf (org-object-attributes obj) attr-key) attr-val) 
                 (push obj results))) 
             *object-store*)
    results))
