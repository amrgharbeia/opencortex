import re

filepath = 'skills/org-skill-shell-actuator.org'
with open(filepath, 'r') as f:
    content = f.read()

# Replace the problematic blocks with known good versions
# Block 1: Whitelist
old_block_1 = """#+begin_src lisp
(defparameter *allowed-commands* '("ls" "git" "rg" "grep" "date" "echo" "cat" "node" "python3" "sbcl"))
#+end_src"""

# Block 2: Metacharacters (Fixing the backquote literal)
old_block_2 = """#+begin_src lisp
(defparameter *shell-metacharacters* '(#\\; #\\& #\\| #\\> #\\< #\\$ #\\` #\\\\ #\\!)
  "Characters that are banned in shell commands to prevent injection.")
#+end_src"""

# Block 3: execute-shell-safely (Ensuring backquotes are correct)
new_execute = """#+begin_src lisp
(defun execute-shell-safely (action context)
  (let* ((payload (getf action :payload))
         (cmd-string (getf payload :cmd))
         (executable (car (uiop:split-string (string-trim " " cmd-string) :separator '(#\\Space)))))
    
    (cond
      ((not (shell-command-safe-p cmd-string))
       (opencortex:inject-stimulus 
        `(:TYPE :EVENT :PAYLOAD (:SENSOR :shell-response :cmd ,cmd-string :stdout "" :stderr "ERROR - Security Violation: Dangerous metacharacters detected." :exit-code 1))
        :stream (getf context :reply-stream)))
      
      ((not (member executable *allowed-commands* :test #'string=))
       (opencortex:inject-stimulus 
        `(:TYPE :EVENT :PAYLOAD (:SENSOR :shell-response :cmd ,cmd-string :stdout "" :stderr "ERROR - Command not in security whitelist." :exit-code 1))
        :stream (getf context :reply-stream)))
      
      (t
       (multiple-value-bind (stdout stderr exit-code)
           (uiop:run-program cmd-string :output :string :error-output :string :ignore-error-status t)
         (opencortex:inject-stimulus 
          `(:TYPE :EVENT :PAYLOAD (:SENSOR :shell-response :cmd ,cmd-string :stdout ,(or stdout "") :stderr ,(or stderr "") :exit-code ,exit-code))
          :stream (getf context :reply-stream)))))))
#+end_src"""

# We'll just overwrite the whole file implementation section to be safe
# (This is a bit drastic but avoids the parsing issues)
