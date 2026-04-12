(in-package :org-agent)

(defstruct skill name priority dependencies trigger-fn neuro-prompt symbolic-fn)

(defvar *skill-catalog* (make-hash-table :test 'equal)
  "A stateful tracking table for all skill files discovered in the environment.")

(defstruct skill-entry 
  filename 
  (status :discovered) ;; :discovered, :loading, :ready, :failed
  error-log
  (load-time 0))

(defun find-triggered-skill (context)
  "Returns the highest priority skill whose trigger condition matches the context."
  (let ((triggered nil))
    (maphash (lambda (name skill) 
               (declare (ignore name)) 
               (when (ignore-errors (funcall (skill-trigger-fn skill) context)) 
                 (push skill triggered))) 
             *skills-registry*)
    (first (sort triggered #'> :key #'skill-priority))))

(defmacro defskill (name &key priority dependencies trigger neuro symbolic)
  "Registers a new skill into the global registry."
  `(setf (gethash (string-downcase (string ,name)) *skills-registry*)
         (make-skill :name (string-downcase (string ,name)) 
                     :priority (or ,priority 10) 
                     :dependencies ,dependencies
                     :trigger-fn ,trigger 
                     :neuro-prompt ,neuro 
                     :symbolic-fn ,symbolic)))

(defun resolve-skill-dependencies (skill-name)
  "Recursively resolves dependencies for a given skill name."
  (let ((resolved nil) (seen nil))
    (labels ((visit (name) 
               (unless (member name seen :test #'equal) 
                 (push name seen)
                 (let ((skill (gethash (string-downcase (string name)) *skills-registry*)))
                   (when skill 
                     (dolist (dep (skill-dependencies skill)) 
                       (visit dep))))
                 (push name resolved))))
      (visit skill-name) 
      (nreverse resolved))))

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
        (id-to-file (make-hash-table :test 'equal))
        (result nil)
        (visited (make-hash-table :test 'equal))
        (stack (make-hash-table :test 'equal)))
    (dolist (file files)
      (let ((filename (pathname-name file)))
        (multiple-value-bind (id deps) (parse-skill-metadata file)
          (setf (gethash (string-downcase filename) id-to-file) file)
          (when id (setf (gethash (string-downcase id) id-to-file) file))
          (setf (gethash (string-downcase filename) adj) deps))))
    (labels ((visit (file)
               (let* ((filename (pathname-name file))
                      (node-key (string-downcase filename)))
                 (unless (gethash node-key visited)
                   (setf (gethash node-key stack) t)
                   (dolist (dep (gethash node-key adj))
                     (let* ((dep-id (if (and (> (length dep) 3) (uiop:string-prefix-p "id:" (string-downcase dep)))
                                        (subseq dep 3)
                                        dep))
                            (dep-file (gethash (string-downcase dep-id) id-to-file)))
                       (when dep-file
                         (let ((dep-filename (pathname-name dep-file)))
                           (if (gethash (string-downcase dep-filename) stack)
                               (error "Circular dependency detected: ~a -> ~a" filename dep-filename)
                               (visit dep-file))))))
                   (setf (gethash node-key stack) nil)
                   (setf (gethash node-key visited) t)
                   (push file result)))))
      (let ((filenames (sort (mapcar #'pathname-name files) #'string<)))
        (dolist (name filenames)
          (let ((file (gethash (string-downcase name) id-to-file)))
            (when file (visit file)))))
      result)))

(defun validate-lisp-syntax (code-string)
  "Checks if a string contains valid, readable Common Lisp forms."
  (handler-case 
      (let ((*read-eval* nil)) 
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof) until (eq form :eof)) 
          (values t nil)))
    (error (c) (values nil (format nil "~a" c)))))

(defun load-skill-from-org (filepath)
  "Parses and evaluates Lisp blocks from an Org file into a jailed package."
  (let* ((skill-base-name (pathname-name filepath))
         (entry (or (gethash skill-base-name *skill-catalog*) (make-skill-entry :filename skill-base-name))))
    (setf (skill-entry-status entry) :loading)
    (setf (gethash skill-base-name *skill-catalog*) entry)
    
    (handler-case
        (let* ((content (uiop:read-file-string filepath)) 
               (lines (uiop:split-string content :separator '(#\Newline)))
               (in-lisp-block nil) 
               (lisp-code "") 
               (pkg-name (intern (string-upcase (format nil "ORG-AGENT.SKILLS.~a" skill-base-name)) :keyword)))
          
          (dolist (line lines)
            (let ((clean-line (string-trim '(#\Space #\Tab #\Return) line)))
              (cond ((uiop:string-prefix-p "#+begin_src lisp" (string-downcase clean-line))
                     ;; Only load blocks that are NOT tangled to src/ or elsewhere
                     (if (search ":tangle" (string-downcase clean-line))
                         (setf in-lisp-block nil)
                         (setf in-lisp-block t)))
                    ((uiop:string-prefix-p "#+end_src" (string-downcase clean-line))
                     (setf in-lisp-block nil))
                    (in-lisp-block 
                     (unless (or (uiop:string-prefix-p ":PROPERTIES:" (string-upcase clean-line))
                                 (uiop:string-prefix-p ":END:" (string-upcase clean-line)))
                       (setf lisp-code (concatenate 'string lisp-code line (string #\Newline))))))))
          
          (if (= (length lisp-code) 0)
              (progn (setf (skill-entry-status entry) :ready) t) ;; Valid empty skill
              (progn
                ;; PRE-FLIGHT: Syntax Validation
                (multiple-value-bind (valid-p err) (validate-lisp-syntax lisp-code)
                  (unless valid-p
                    (error "Syntax Error: ~a" err)))
                
                (kernel-log "KERNEL: Jailing skill '~a' in package ~a" skill-base-name pkg-name)
                (unless (find-package pkg-name)
                  (let ((new-pkg (make-package pkg-name :use '(:cl))))
                    (do-external-symbols (sym (find-package :org-agent)) (shadowing-import sym new-pkg))))
                
                (let ((*read-eval* nil) (*package* (find-package pkg-name)))
                  (eval (read-from-string (format nil "(progn ~a)" lisp-code))))
                
                (setf (skill-entry-status entry) :ready)
                t)))
      (error (c)
        (let ((msg (format nil "~a" c)))
          (kernel-log "LOADER ERROR in skill '~a': ~a" skill-base-name msg)
          (setf (skill-entry-status entry) :failed)
          (setf (skill-entry-error-log entry) msg)
          nil)))))

(defun load-skill-with-timeout (filepath timeout-seconds)
  "Loads a skill Org file with a hard execution timeout."
  (let* ((finished nil)
         (thread (bt:make-thread (lambda () 
                                   (if (load-skill-from-org filepath)
                                       (setf finished t)
                                       (setf finished :error)))
                                 :name (format nil "loader-~a" (pathname-name filepath))))
         (start-time (get-internal-real-time))
         (timeout-units (truncate (* timeout-seconds internal-time-units-per-second))))
    (loop 
      (when (eq finished t) (return :success))
      (when (eq finished :error) (return :error))
      (unless (bt:thread-alive-p thread) (return :error))
      (when (> (- (get-internal-real-time) start-time) timeout-units)
        (kernel-log "KERNEL: Timing out skill ~a..." (pathname-name filepath))
        #+sbcl (sb-thread:terminate-thread thread)
        #-sbcl (bt:destroy-thread thread)
        (return :timeout))
      (sleep 0.05))))

(defun initialize-all-skills ()
  "Scans the directory defined by SKILLS_DIR and hot-loads skills using topological order."
  (let* ((env-path (uiop:getenv "SKILLS_DIR"))
         (skills-dir-str (or env-path (namestring (merge-pathnames "notes/" (user-homedir-pathname)))))
         (resolved-path (context-resolve-path skills-dir-str))
         (skills-dir (if resolved-path (uiop:ensure-directory-pathname resolved-path) nil)))
    
    (unless (and skills-dir (uiop:directory-exists-p skills-dir))
      (kernel-log "KERNEL ERROR: Skills directory not found: ~a" skills-dir-str)
      (return-from initialize-all-skills nil))

    (let ((sorted-files (topological-sort-skills skills-dir)))
      ;; MANDATE: The Executive Soul must be present
      (unless (member "org-skill-agent" sorted-files :key #'pathname-name :test #'string-equal)
        (error "BOOT FAILURE: org-skill-agent.org not found in skills directory."))
      
      (kernel-log "==================================================")
      (kernel-log " LOADER: Initializing ~a skills..." (length sorted-files))
      
      (dolist (file sorted-files)
        (let ((skill-name (pathname-name file)))
          (kernel-log " LOADER: Loading ~a..." skill-name)
          (load-skill-with-timeout file 5)))
      
      ;; Final Summary
      (let ((ready 0) (failed 0))
        (maphash (lambda (k v) 
                   (declare (ignore k))
                   (if (eq (skill-entry-status v) :ready) (incf ready) (incf failed)))
                 *skill-catalog*)
        (kernel-log " LOADER: Boot Complete. [Ready: ~a] [Failed: ~a]" ready failed)
        (kernel-log "==================================================")
        (values ready failed)))))

(defun generate-tool-belt-prompt ()
  "Aggregates all registered cognitive tools into a descriptive prompt."
  (let ((output (format nil "AVAILABLE TOOLS:
You can call tools by returning a Lisp plist: (:target :tool :action :call :tool <name> :args (...))

EXAMPLES:
(:target :tool :action :call :tool \"eval\" :args (:code \"(+ 1 1)\"))
(:target :tool :action :call :tool \"grep-search\" :args (:pattern \"sovereignty\"))
(:target :tool :action :call :tool \"shell\" :args (:cmd \"ls -la\"))

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

(def-cognitive-tool :eval "Evaluates raw Common Lisp code in the kernel image. Use this for complex calculations or internal state inspection."
  ((:code :type :string :description "The Lisp code to evaluate"))
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
  ((:pattern :type :string :description "The regex pattern to search for")
   (:dir :type :string :description "Directory to search in (default is project root)"))
  :body (lambda (args)
          (let ((pattern (getf args :pattern))
                (dir (or (getf args :dir) (uiop:getenv "MEMEX_DIR"))))
            (uiop:run-program (list "grep" "-r" "-n" "--exclude-dir=node_modules" pattern dir) 
                              :output :string :ignore-error-status t))))

(def-cognitive-tool :shell "Executes a shell command on the local machine. Use this for file operations, system checks, or running tests."
  ((:cmd :type :string :description "The full bash command to execute"))
  :guard (lambda (args context)
           (declare (ignore context))
           (let ((cmd (getf args :cmd)))
             (not (or (search "rm -rf /" cmd) (search ":(){ :|:& };:" cmd)))))
  :body (lambda (args)
          (let ((cmd (getf args :cmd)))
            (multiple-value-bind (out err code)
                (uiop:run-program (list "bash" "-c" cmd) :output :string :error-output :string :ignore-error-status t)
              (format nil "EXIT-CODE: ~a~%~%STDOUT:~%~a~%~%STDERR:~%~a" code out err)))))
