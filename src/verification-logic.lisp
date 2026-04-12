(in-package :org-agent)

(defvar *formal-invariants* (make-hash-table :test 'equal)
  "Registry of security invariants used by the Formal Verification Gate.")

(defmacro def-invariant (name action-type (action context) &body body)
  "Defines a formal security invariant. 
   BODY must return T for safe actions and NIL for unsafe ones."
  `(setf (gethash (string-downcase (string ',name)) *formal-invariants*)
         (list :name ',name
               :type ,action-type
               :logic (lambda (,action ,context) ,@body))))

(def-invariant path-confinement :all (action context)
  "Forces all path-based operations to reside within the Sovereign Memex."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (path (or (getf payload :file) (getf payload :path)))
         (cmd (getf payload :cmd))
         (memex-root (or (uiop:getenv "MEMEX_DIR") "/home/user/memex")))
    (cond
      ;; If a path is explicitly provided, verify it is absolute and within root
      (path 
       (let ((truename (ignore-errors (namestring (truename path)))))
         (if truename
             (str:starts-with-p memex-root truename)
             ;; If file doesn't exist yet, check string prefix
             (str:starts-with-p memex-root path))))
      ;; If it's a shell command, check for absolute paths outside memex
      (cmd 
       (not (cl-ppcre:scan "(^|\\s)/((etc|var|proc|root|sys)|(home/(?!user/memex)))" cmd)))
      (t t))))

(def-invariant no-network-exfil :shell (action context)
  "Prevents shell commands from establishing unauthorized external connections."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (cmd (getf payload :cmd)))
    (if (and cmd (stringp cmd))
        (let ((forbidden-tools '("nc" "netcat" "ssh" "scp" "rsync" "ftp" "telnet")))
          (not (some (lambda (tool) (cl-ppcre:scan (format nil "(^|\\s)~a(\\s|$)" tool) cmd)) 
                     forbidden-tools)))
        t)))

(defun verify-action-formally (action context)
  "Symbolically proves that ACTION satisfies all applicable security invariants."
  (let ((action-target (getf action :target))
        (action-type (getf action :type))
        (all-passed t))
    (maphash (lambda (id inv)
               (declare (ignore id))
               (let ((inv-type (getf inv :type))
                     (inv-logic (getf inv :logic))
                     (inv-name (getf inv :name)))
                 (when (or (eq inv-type :all)
                           (eq inv-type action-target)
                           (eq inv-type action-type))
                   (unless (funcall inv-logic action context)
                     (harness-log "FORMAL FAILURE: Action ~s violated invariant ~a" action inv-name)
                     (setf all-passed nil)))))
             *formal-invariants*)
    all-passed))

(defskill :skill-formal-verification
  :priority 95 ; Just below Bouncer
  :trigger (lambda (context) (declare (ignore context)) nil) ; Middleware only
  :neuro nil
  :symbolic (lambda (action context)
              (if (verify-action-formally action context)
                  action
                  (let ((err (format nil "Formal verification failed for action: ~s" action)))
                    `(:type :log :payload (:level :error :text ,err))))))
