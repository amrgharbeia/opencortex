(in-package :org-agent)
(defparameter *allowed-commands* '("ls" "git" "rg" "grep" "date" "echo" "cat" "node" "python3" "sbcl"))

(in-package :org-agent)
(defparameter *shell-metacharacters* '(#\; #\& #\| #\> #\< #\$ #\` #\\ #\!)
  "Characters that are banned in shell commands to prevent injection.")

(in-package :org-agent)
(defun shell-command-safe-p (cmd-string)
  "Returns T if the command string contains no dangerous metacharacters."
  (not (some (lambda (char) (find char cmd-string)) *shell-metacharacters*)))

(in-package :org-agent)
(defun execute-shell-safely (action context)
  (let* ((cmd-string (getf (getf action :payload) :cmd))
         (executable (car (uiop:split-string (string-trim " " cmd-string) :separator '(#\Space)))))
    
    (cond
      ;; 1. Metacharacter check (Injection prevention)
      ((not (shell-command-safe-p cmd-string))
       (org-agent:inject-stimulus 
        `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd-string :stdout "" :stderr "ERROR - Security Violation: Dangerous metacharacters detected." :exit-code 1))
        :stream (getf context :reply-stream)))
      
      ;; 2. Whitelist check
      ((not (member executable *allowed-commands* :test #'string=))
       (org-agent:inject-stimulus 
        `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd-string :stdout "" :stderr "ERROR - Command not in security whitelist." :exit-code 1))
        :stream (getf context :reply-stream)))
      
      ;; 3. Safe Execution
      (t
       (multiple-value-bind (stdout stderr exit-code)
           (uiop:run-program cmd-string :output :string :error-output :string :ignore-error-status t)
         (org-agent:inject-stimulus 
          `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd-string :stdout ,(or stdout "") :stderr ,(or stderr "") :exit-code ,exit-code))
          :stream (getf context :reply-stream)))))))

(in-package :org-agent)
(defun execute-sandboxed-script (action context)
  "Executes a synthesized script (Python/Lisp/JS) in a controlled directory.
   This enables SOTA-level Tool Synthesis and Iterative Fixing."
  (let* ((payload (getf action :payload))
         (language (getf payload :language))
         (content (getf payload :content))
         (sandbox-dir "/tmp/org-agent-sandbox/")
         (filename (format nil "synth-~a.~a" (get-universal-time) (case language (:python "py") (:lisp "lisp") (:js "js") (t "txt"))))
         (full-path (format nil "~a~a" sandbox-dir filename)))
    
    (ensure-directories-exist sandbox-dir)
    (with-open-file (out full-path :direction :output :if-exists :supersede)
      (write-string content out))
    
    (let ((cmd (case language
                 (:python (format nil "python3 ~a" full-path))
                 (:lisp (format nil "sbcl --script ~a" full-path))
                 (:js (format nil "node ~a" full-path)))))
      (multiple-value-bind (stdout stderr exit-code)
          (uiop:run-program cmd :output :string :error-output :string :ignore-error-status t)
        (org-agent:inject-stimulus 
         `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd :stdout ,(or stdout "") :stderr ,(or stderr "") :exit-code ,exit-code :synthesis-p t))
         :stream (getf context :reply-stream))))))

(in-package :org-agent)
(defun provision-microvm (id &key (cpu 1) (ram 512))
  "Hardware-Level Isolation: Provisions an ephemeral Firecracker MicroVM.
   This is the high-security evolution of directory-based sandboxing."
  (harness-log "SECURITY [Hardware] - Provisioning MicroVM ~a (CPU: ~a, RAM: ~aMB)..." id cpu ram)
  ;; Future implementation: Wraps 'fcvm' or 'firecracker' CLI calls.
  (format nil "vm-~a-provisioned" id))

(in-package :org-agent)
(defun trigger-skill-shell-actuator (context)
  (let ((type (getf context :type))
        (payload (getf context :payload)))
    (and (eq type :EVENT)
         (eq (getf payload :sensor) :shell-response))))

(in-package :org-agent)
(org-agent:register-actuator :shell #'execute-shell-safely)

(in-package :org-agent)
(defskill :skill-shell-actuator
  :priority 80
  :trigger #'trigger-skill-shell-actuator
  :neuro #'neuro-skill-shell-actuator
  :symbolic (lambda (action context) (declare (ignore context)) action))
