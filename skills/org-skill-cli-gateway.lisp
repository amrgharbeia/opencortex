(in-package :opencortex)

(defun cli-process-input (text)
  "Processes raw text from the command line."
  (inject-stimulus (list :type :EVENT 
                         :payload (list :sensor :user-input :text text) 
                         :meta (list :source :CLI))))

(defskill :skill-cli-gateway
  :priority 100
  :trigger (lambda (ctx) (eq (getf (getf ctx :meta) :source) :CLI))
  :deterministic (lambda (action ctx) (declare (ignore ctx)) action))
