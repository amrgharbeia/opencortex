(defparameter *allowed-commands* '("ls" "git" "rg" "grep" "date" "echo" "cat" "node" "python3" "sbcl"))

(defun execute-shell-safely (action context)
  (let* ((cmd-string (getf (getf action :payload) :cmd))
         (executable (car (uiop:split-string cmd-string :separator '(#\Space)))))
    (if (member executable *allowed-commands* :test #'string=)
        (multiple-value-bind (stdout stderr exit-code)
            (uiop:run-program cmd-string :output :string :error-output :string :ignore-error-status t)
          (org-agent:inject-stimulus 
           `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd-string :stdout ,(or stdout "") :stderr ,(or stderr "") :exit-code ,exit-code))
           :stream (getf context :reply-stream)))
        (org-agent:inject-stimulus 
         `(:type :EVENT :payload (:sensor :shell-response :cmd ,cmd-string :stdout "" :stderr "ERROR - Command not in security whitelist." :exit-code 1))
         :stream (getf context :reply-stream)))))

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

(defun provision-microvm (id &key (cpu 1) (ram 512))
  "Hardware-Level Isolation: Provisions an ephemeral Firecracker MicroVM.
   This is the high-security evolution of directory-based sandboxing."
  (kernel-log "SECURITY [Hardware] - Provisioning MicroVM ~a (CPU: ~a, RAM: ~aMB)..." id cpu ram)
  ;; Future implementation: Wraps 'fcvm' or 'firecracker' CLI calls.
  (format nil "vm-~a-provisioned" id))

(defun trigger-skill-shell-actuator (context)
  (let ((type (getf context :type))
        (payload (getf context :payload)))
    (and (eq type :EVENT)
         (eq (getf payload :sensor) :shell-response))))

(defun neuro-skill-shell-actuator (context)
  (let* ((p (getf context :payload))
         (cmd (getf p :cmd))
         (stdout (getf p :stdout))
         (stderr (getf p :stderr))
         (exit-code (getf p :exit-code))
         (synthesis-p (getf p :synthesis-p)))
    (if synthesis-p
        (format nil "
          TOOL SYNTHESIS RESULT:
          Command: ~a (Exit: ~a)
          STDOUT: ~a
          STDERR: ~a
          
          TASK: 
          If the command failed (Exit != 0), analyze the STDERR and propose a FIX for the script.
          If it succeeded, use the STDOUT to complete the original goal.
        " cmd exit-code stdout stderr)
        (let ((result-text (format nil "* Shell Command Result\n- Command: ~a\n- Exit Code: ~a\n\n** STDOUT\n#+begin_example\n~a\n#+end_example\n\n** STDERR\n#+begin_example\n~a\n#+end_example"
                                   cmd exit-code stdout stderr)))
          `(:type :request :target :emacs :payload (:action :insert-at-end :buffer "*org-agent-chat*" :text ,result-text))))))
