(in-package :opencortex)

(defun shell-execute (action context)
  "Executes a bash command and returns the output."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (cmd (getf payload :cmd)))
    (harness-log "ACT [Shell]: ~a" cmd)
    (multiple-value-bind (out err code)
        (uiop:run-program (list "bash" "-c" cmd) :output :string :error-output :string :ignore-error-status t)
      (if (= code 0)
          out
          (format nil "ERROR [~a]: ~a" code err)))))

(register-actuator :shell #'shell-execute)

(defskill :skill-shell-actuator
  :priority 50
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
