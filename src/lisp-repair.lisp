(in-package :org-agent)

(defun count-char (char string)
  (let ((count 0))
    (loop for c across string
          when (char= c char)
            do (incf count))
    count))

(defun deterministic-repair (code)
  "Attempts instant fixes on broken Lisp code (e.g. balancing parens)."
  (let* ((open-parens (count-char #\( code))
         (close-parens (count-char #\) code))
         (diff (- open-parens close-parens)))
    (if (> diff 0)
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

(defskill :skill-lisp-repair
  :priority 90
  :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :syntax-error))
  :neuro nil ;; Handled deterministically in symbolic or manually via ask-neuro
  :symbolic (lambda (action context)
              (declare (ignore action))
              (let* ((payload (getf context :payload))
                     (code (getf payload :code))
                     (error-msg (getf payload :error)))
                (kernel-log "SYNTAX GATE: Reacting to broken Lisp stimulus...")
                (let ((fast-fix (deterministic-repair code)))
                  (handler-case
                      (let ((repaired (read-from-string fast-fix)))
                        (kernel-log "SYNTAX GATE: Deterministic repair SUCCESS.")
                        repaired)
                    (error ()
                      (kernel-log "SYNTAX GATE: Deterministic repair failed. Escalating...")
                      (let ((deep-fix (neural-repair code error-msg)))
                        (handler-case
                            (let ((repaired (read-from-string deep-fix)))
                              (kernel-log "SYNTAX GATE: Neural repair SUCCESS.")
                              repaired)
                          (error ()
                            (kernel-log "SYNTAX GATE: Neural repair failed.")
                            (list :type :LOG :payload (list :text "Lisp Repair Failed.")))))))))))
