(in-package :org-agent)

(defun count-char (char string)
  (let ((count 0))
    (loop for c across string
          when (char= c char)
            do (incf count))
    count))

(defun deterministic-repair (code)
  "Attempts instant fixes on broken Lisp code."
  (let* ((open-parens (count-char #\( code))
         (close-parens (count-char #\) code))
         (diff (- open-parens close-parens)))
    (if (> diff 0)
        ;; Append missing closing parens
        (concatenate 'string code (make-string diff :initial-element #\)))
        code)))

(defun neural-repair (code error-message)
  "Uses System 1 to deeply repair the syntax structure."
  (let ((prompt (format nil "The following Lisp code failed to parse. 
ERROR: ~a
CODE: ~a
MANDATE: Output EXACTLY ONE valid Common Lisp list. Do not explain. Do not use markdown blocks."
                        error-message code))
        (system-prompt "You are a Lisp Syntax Repair Actuator. Return only valid, balanced Lisp code."))
    (let ((repaired (ask-neuro prompt :system-prompt system-prompt)))
      (string-trim '(#\Space #\Newline #\Tab) repaired))))

(defun repair-lisp-syntax (code error-message)
  "The entry point called by the neuro-gate when read-from-string fails."
  (kernel-log "SYNTAX GATE: Intercepted broken Lisp. Attempting deterministic repair...")
  (let ((fast-fix (deterministic-repair code)))
    (handler-case
        (read-from-string fast-fix)
      (error ()
        (kernel-log "SYNTAX GATE: Deterministic repair failed. Escalating to neural repair...")
        (let ((deep-fix (neural-repair code error-message)))
          (handler-case
              (read-from-string deep-fix)
            (error ()
              (kernel-log "SYNTAX GATE: Neural repair failed.")
              nil)))))))

(defskill :skill-lisp-repair
  :priority 90
  :trigger (lambda (ctx) (declare (ignore ctx)) nil) ;; Passive interceptor
  :neuro nil
  :symbolic nil)
