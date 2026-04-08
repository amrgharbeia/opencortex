(in-package :org-agent)

(defvar *skills-registry* (make-hash-table :test 'equal))

(defstruct skill name priority dependencies trigger-fn neuro-prompt symbolic-fn)

(defvar *cognitive-tools* (make-hash-table :test 'equal))

(defstruct cognitive-tool name description parameters guard body)

(defmacro def-cognitive-tool (name description &key parameters guard body)
  `(setf (gethash (string-downcase (string ,name)) *cognitive-tools*)
         (make-cognitive-tool :name (string-downcase (string ,name))
                             :description ,description
                             :parameters ',parameters
                             :guard ,guard
                             :body ,body)))

(defun generate-tool-belt-prompt ()
  (let ((output (format nil "AVAILABLE TOOLS:
You can call tools by returning a Lisp plist: (:target :tool :action :call :tool <name> :args (...))

---
")))
    (maphash (lambda (name tool)
               (setf output (concatenate 'string output
                                         (format nil "- ~a: ~a~%  Parameters: ~s~%~%"
                                                 name
                                                 (cognitive-tool-description tool)
                                                 (cognitive-tool-parameters tool)))))
             *cognitive-tools*)
    output))

(defmacro defskill (name &key priority dependencies trigger neuro symbolic)
  `(setf (gethash ,(string-downcase (string name)) *skills-registry*)
         (make-skill :name ,(string-downcase (string name)) :priority (or ,priority 10) :dependencies ,dependencies
                     :trigger-fn ,trigger :neuro-prompt ,neuro :symbolic-fn ,symbolic)))

(defun find-triggered-skill (context)
  (let ((triggered nil))
    (maphash (lambda (name skill) (declare (ignore name)) (when (ignore-errors (funcall (skill-trigger-fn skill) context)) (push skill triggered))) *skills-registry*)
    (first (sort triggered #'> :key #'skill-priority))))

(defun resolve-skill-dependencies (skill-name)
  (let ((resolved nil) (seen nil))
    (labels ((visit (name) (unless (member name seen :test #'equal) (push name seen)
                             (let ((skill (gethash (string-downcase (string name)) *skills-registry*)))
                               (when skill (dolist (dep (skill-dependencies skill)) (visit dep))))
                             (push name resolved))))
      (visit skill-name) (nreverse resolved))))

;; --- Boot Sequence & Micro-Loader ---

(defun parse-skill-metadata (filepath)
  "Extracts ID and DEPENDS_ON tags using robust line-scanning."
  (let ((dependencies nil)
        (id nil))
    (with-open-file (stream filepath)
      (loop for line = (read-line stream nil :eof)
            until (eq line :eof)
            do (let ((clean (string-trim '(#\Space #\Tab #\Return #\Newline) line)))
                 (cond
                   ((uiop:string-prefix-p "#+DEPENDS_ON:" (string-upcase clean))
                    (let* ((deps-part (string-trim " " (subseq clean 13))))
                      (setf dependencies (append dependencies 
                                                 (mapcar (lambda (s) (string-trim "[] " s))
                                                         (uiop:split-string deps-part :separator '(#\Space #\Tab)))))))
                   ((uiop:string-prefix-p ":ID:" (string-upcase clean))
                    (setf id (string-trim '(#\Space #\Tab) (subseq clean 4))))))))
    (values id (remove-if (lambda (s) (= 0 (length s))) dependencies))))

(defun topological-sort-skills (skills-dir)
  "Returns a list of skill filepaths sorted by dependency (dependencies first)."
  (let ((files (uiop:directory-files skills-dir "org-skill-*.org"))
        (adj (make-hash-table :test 'equal))
        (path-map (make-hash-table :test 'equal))
        (result nil)
        (visited (make-hash-table :test 'equal))
        (stack (make-hash-table :test 'equal)))
    (dolist (file files)
      (let ((name (pathname-name file)))
        (setf (gethash name path-map) file)
        (multiple-value-bind (id deps) (parse-skill-metadata file)
          (declare (ignore id))
          (let ((clean-deps (mapcar (lambda (d) (if (uiop:string-prefix-p "id:" (string-downcase d)) (subseq d 3) d)) deps)))
            (setf (gethash name adj) clean-deps)))))
    
    (labels ((visit (node)
               (let ((node-name (string-downcase node)))
                 (when (gethash node-name stack) (error "Circular dependency detected: ~a" node-name))
                 (unless (gethash node-name visited)
                   (setf (gethash node-name stack) t)
                   (dolist (dep (gethash node-name adj))
                     (when (gethash (string-downcase dep) path-map)
                       (visit (string-downcase dep))))
                   (setf (gethash node-name stack) nil)
                   (setf (gethash node-name visited) t)
                   (push (gethash node-name path-map) result)))))
      (let ((names nil))
        (maphash (lambda (k v) (declare (ignore v)) (push k names)) path-map)
        (dolist (name (sort names #'string<))
          (visit name)))
      (nreverse result))))

(defun load-skill-with-timeout (filepath timeout-seconds)
  "Loads a skill Org file with a hard execution timeout."
  (let* ((finished nil)
         (thread (bt:make-thread (lambda () 
                                   (load-skill-from-org filepath)
                                   (setf finished t)) 
                                 :name (format nil "loader-~a" (pathname-name filepath))))
         (start-time (get-internal-real-time))
         (timeout-units (* timeout-seconds internal-time-units-per-second)))
    (loop 
      (when finished (return :success))
      (unless (bt:thread-alive-p thread) (return :error))
      (when (> (- (get-internal-real-time) start-time) timeout-units)
        #+sbcl (sb-thread:terminate-thread thread)
        #-sbcl (bt:destroy-thread thread)
        (kernel-log "KERNEL ERROR: Timeout loading skill ~a" (pathname-name filepath))
        (return :timeout))
      (sleep 0.1))))

(defun load-skill-from-org (filepath)
  (when (uiop:file-exists-p filepath)
    (let* ((content (uiop:read-file-string filepath)) (lines (uiop:split-string content :separator '(#\Newline)))
           (in-lisp-block nil) (lisp-code "") (skill-base-name (pathname-name filepath))
           (pkg-name (intern (string-upcase (format nil "ORG-AGENT.SKILLS.~a" skill-base-name)) :keyword)))
      (dolist (line lines)
        (let ((clean-line (string-trim '(#\Space #\Tab #\Return) line)))
          (cond ((uiop:string-prefix-p "#+begin_src lisp" (string-downcase clean-line)) (setf in-lisp-block t))
                ((uiop:string-prefix-p "#+end_src" (string-downcase clean-line)) (setf in-lisp-block nil))
                (in-lisp-block (setf lisp-code (concatenate 'string lisp-code line (string #\Newline)))))))
      (when (> (length lisp-code) 0)
        (kernel-log "KERNEL: Jailing skill '~a' in package ~a" skill-base-name pkg-name)
        (unless (find-package pkg-name)
          (let ((new-pkg (make-package pkg-name :use '(:cl))))
            (do-external-symbols (sym (find-package :org-agent)) (shadowing-import sym new-pkg))))
        (let ((*read-eval* nil) (*package* (find-package pkg-name)))
          (handler-case (eval (read-from-string (format nil "(progn ~a)" lisp-code)))
            (error (c) 
              (kernel-log "READER ERROR in skill '~a': ~a~%" skill-base-name c)
              (error c))))))))

(defun validate-lisp-syntax (code-string)
  (handler-case (let ((*read-eval* nil)) (with-input-from-string (stream (format nil "(progn ~a)" code-string))
                                          (loop for form = (read stream nil :eof) until (eq form :eof)) (values t nil)))
    (error (c) (values nil (format nil "~a" c)))))

(def-cognitive-tool :eval "Evaluates raw Common Lisp code in the kernel image."
  :parameters ((:code :type :string :description "The Lisp code to evaluate"))
  :guard (lambda (args context)
           (declare (ignore context))
           (let ((code (getf args :code)))
             (let ((harness-pkg (find-package :org-agent.skills.org-skill-safety-harness)))
               (if harness-pkg 
                   (uiop:symbol-call :org-agent.skills.org-skill-safety-harness :safety-harness-validate code)
                   t))))
  :body (lambda (args)
          (let ((code (getf args :code)))
            (handler-case (let ((result (eval (read-from-string code))))
                            (format nil "~s" result))
              (error (c) (format nil "ERROR: ~a" c))))))

(def-cognitive-tool :grep-search "Searches for a pattern in the project files."
  :parameters ((:pattern :type :string :description "The regex pattern to search for")
               (:dir :type :string :description "Directory to search in (default is project root)"))
  :body (lambda (args)
          (let ((pattern (getf args :pattern))
                (dir (or (getf args :dir) (uiop:getenv "MEMEX_DIR"))))
            (uiop:run-program (list "grep" "-r" "-n" "--exclude-dir=node_modules" pattern dir) 
                              :output :string :ignore-error-status t))))

(def-cognitive-tool :shell "Executes a shell command on the local machine."
  :parameters ((:cmd :type :string :description "The full bash command to execute"))
  :guard (lambda (args context)
           (declare (ignore context))
           (let ((cmd (getf args :cmd)))
             (not (or (search "rm -rf /" cmd) (search ":(){ :|:& };:" cmd)))))
  :body (lambda (args)
          (let ((cmd (getf args :cmd)))
            (multiple-value-bind (out err code)
                (uiop:run-program (list "bash" "-c" cmd) :output :string :error-output :string :ignore-error-status t)
              (format nil "EXIT-CODE: ~a~%~%STDOUT:~%~a~%~%STDERR:~%~a" code out err)))))
