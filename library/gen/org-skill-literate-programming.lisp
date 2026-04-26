(in-package :opencortex)

(defun literate-check-block-balance (code-string)
  "Returns T if CODE-STRING has balanced parentheses, brackets, and strings.

   Ignores comments (after ;) and tracks string contents to avoid
   counting parens inside string literals."
  (let ((depth 0) (in-string nil) (escaped nil))
    (dotimes (i (length code-string))
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
               (decf depth))))))
    (if (zerop depth)
        t
        (values nil (format nil "Unbalanced parens: depth ~a at end of string" depth)))))

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
                      (setf idx (+ end-pos 9)))))))))))

(defvar *tangle-targets*
  '(("skills/org-skill-engineering-standards.org" . "library/gen/org-skill-engineering-standards.lisp")
    ("skills/org-skill-literate-programming.org" . "library/gen/org-skill-literate-programming.lisp")
    ("harness/memory.org" . "library/memory.lisp")
    ("harness/loop.org" . "library/loop.lisp")
    ("harness/perceive.org" . "library/perceive.lisp")
    ("harness/reason.org" . "library/reason.lisp")
    ("harness/act.org" . "library/act.lisp")
    ("harness/skills.org" . "library/skills.lisp")
    ("harness/communication.org" . "library/communication.lisp")))

(defvar *lp-project-root* nil)

(defun lp-set-project-root (path)
  (setf *lp-project-root* (uiop:ensure-directory-pathname path)))

(defun check-tangle-sync (&optional (root *lp-project-root*))
  "Returns violation if any tangled .lisp file is newer than its Org source.

This detects direct .lisp edits (which violate the LP workflow)."
  (when root
    (dolist (pair *tangle-targets*)
      (let* ((org-file (merge-pathnames (car pair) root))
             (lisp-file (merge-pathnames (cdr pair) root))
             (org-time (ignore-errors (file-write-date org-file)))
             (lisp-time (ignore-errors (file-write-date lisp-file))))
        (when (and org-time lisp-time (> lisp-time org-time))
          (return-from check-tangle-sync
            (list :type :log
                  :payload (list :text (format nil "LITERATE PROGRAMMING VIOLATION: ~a is newer than ~a. Edit Org source, not .lisp directly."
                                               (file-namestring lisp-file) (file-namestring org-file)))))))))
  nil)

(defskill :skill-literate-programming
  :priority 1100
  :trigger (lambda (ctx)
             (declare (ignore ctx))
             t)
  :probabilistic nil
  :deterministic (lambda (action context)
                   (declare (ignore context))
                   (block skill-literate-programming
                     ;; Check tangle sync before any file modification
                     (let ((file (and (listp action) (getf action :payload) (getf (getf action :payload) :file))))
                       (when file
                         (let ((tangle-check (check-tangle-sync *lp-project-root*)))
                           (when tangle-check
                             (return-from skill-literate-programming
                               (progn
                                 (harness-log "~a" (getf (getf tangle-check :payload) :text))
                                 tangle-check))))))
                     ;; Audit org files for structural balance
                     (when (and (listp action)
                                (stringp (getf action :file)))
                       (let ((file (getf action :file)))
                         (when (and (search ".org" file)
                                    (search "skill" file :test #'string-equal))
                           (let ((issues (literate-audit-org-file file)))
                             (when issues
                               (harness-log "LITERATE PROGRAMMING: Structural issues found in ~a: ~a"
                                            file issues))))))
                     action)))

(defvar *lp-initialized* nil)

(defun lp-init ()
  "Initialize the LP system with project root."
  (unless *lp-initialized*
    (let ((env-root (or (uiop:getenv "OPENCORTEX_ROOT")
                        (uiop:getenv "MEMEX_DIR")
                        "/home/user/memex/projects/opencortex")))
      (lp-set-project-root env-root)
      (setf *lp-initialized* t)
      (harness-log "LITERATE PROGRAMMING: Initialized with root ~a" *lp-project-root*))))

;; Auto-initialize on load
(lp-init)
