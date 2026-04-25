(defun literate-check-block-balance (code-string)
  "Returns T if CODE-STRING has balanced parentheses, brackets, and strings.

   Ignores comments (after ;) and tracks string contents to avoid
   counting parens inside string literals."
  (let ((depth 0) (in-string nil) (escaped nil))
    (dotimes (i (length code-string) (zerop depth))
      (let ((ch (char code-string i)))
        (cond
          ;; Escape handling (affects next char only)
          (escaped (setf escaped nil))
          ((char= ch #\\) (setf escaped t))
          ;; String boundaries
          (in-string (when (char= ch #\") (setf in-string nil)))
          ((char= ch #\") (setf in-string t))
          ;; Comment boundaries (skip to end of line)
          ((char= ch #\;)
           (loop while (and (< i (1- (length code-string)))
                           (not (char= (char code-string (1+ i)) #\Newline)))
                 do (incf i)))
          ;; Structural parens
          ((member ch '(#\( #\[)) (incf depth))
          ((member ch '(#\) #\]))
           (if (<= depth 0)
               (return-from literate-check-block-balance
                 (values nil (format nil "Unexpected close paren at position ~a" i)))
               (decf depth))))))))

(defun literate-audit-org-file (filepath)
  "Audits all tangled lisp blocks in an Org file for structural balance.

   Returns a list of imbalance reports, or NIL if all blocks are balanced."
  (let* ((content (with-open-file (s filepath)
                    (let ((seq (make-string (file-length s))))
                      (read-sequence seq s)
                      seq)))
         (idx 0)
         (reports nil)
         (block-num 0))
    (loop
      (let ((pos (search "#+begin_src lisp" content :start2 idx :test #'string-equal)))
        (when (null pos) (return (nreverse reports)))
        (let* ((eol (or (position #\Newline content :start pos) (length content)))
               (header (subseq content pos eol))
               (header-lower (string-downcase header))
               (tangle-p (and (search ".lisp" header-lower)
                             (not (search ":tangle no" header-lower)))))
          (if (not tangle-p)
              (setf idx (1+ eol))
              (let ((end-pos (search "#+end_src" content :start2 eol :test #'string-equal)))
                (if (null end-pos)
                    (progn
                      (push (list :block (incf block-num) :status :missing-end-src) reports)
                      (return (nreverse reports)))
                    (let ((raw-block (subseq content (1+ eol) end-pos))
                          (clean-lines nil))
                      ;; Strip PROPERTIES drawers and :END: markers
                      (dolist (line (uiop:split-string raw-block :separator '(#\Newline)))
                        (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
                          (when (and (plusp (length trimmed))
                                     (not (string= (subseq trimmed 0 (min 12 (length trimmed))) ":PROPERTIES:"))
                                     (not (string= (subseq trimmed 0 (min 5 (length trimmed))) ":END:")))
                            (push line clean-lines))))
                      (let ((code (format nil "~{~a~^~%~}" (nreverse clean-lines))))
                        (multiple-value-bind (ok reason) (literate-check-block-balance code)
                          (unless ok
                            (push (list :block (incf block-num)
                                       :status :unbalanced
                                       :reason reason
                                       :code code)
                                  reports))))
                      (setf idx (+ end-pos 9))))))))))

(defskill :skill-literate-programming
  :priority 1100
  :trigger (lambda (ctx)
             (declare (ignore ctx))
             ;; Trigger on any skill-related action
             t)
  :probabilistic nil
  :deterministic (lambda (action context)
                   (declare (ignore context))
                   ;; Audit the action's target file if it's an org skill
                   (when (and (listp action)
                              (stringp (getf action :file)))
                     (let ((file (getf action :file)))
                       (when (and (search ".org" file)
                                  (search "skill" file :test #'string-equal))
                         (let ((issues (literate-audit-org-file file)))
                           (when issues
                             (harness-log "LITERATE PROGRAMMING: Structural issues found in ~a: ~a"
                                          file issues))))))
                   action))
