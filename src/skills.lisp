(in-package :org-agent)

;;; ============================================================================
;;; Org-Native Skill Engine
;;; ============================================================================
;;; This module implements the 'Foundry' for new agent capabilities. 
;;; Following the 'Code is Data' philosophy, a skill is defined entirely 
;;; within a single .org file. This allows the agent's logic to live 
;;; co-located with the user's personal notes.

(defvar *skills-registry* (make-hash-table :test 'equal)
  "Global registry of all loaded neurosymbolic skills. 
   Key is the downcased skill name string.")

(defstruct skill
  "The representation of a cognitive capability."
  name         ; Human-readable name (from #+SKILL_NAME)
  priority     ; Integer used to resolve conflicts when multiple skills trigger
  dependencies ; A list of skill names that this skill depends on (Skill Graph)
  trigger-fn   ; Lisp function: (context) -> boolean
  neuro-prompt ; Lisp function: (context) -> prompt-string (System 1)
  symbolic-fn  ; Lisp function: (proposed-action context) -> approved-action (System 2)
  )

(defmacro defskill (name &key priority dependencies trigger neuro symbolic)
  "The primary macro for registering a new skill. 
   Designed to be called from inside Org-mode Lisp blocks."
  `(setf (gethash ,(string-downcase (string name)) *skills-registry*)
         (make-skill :name ,(string-downcase (string name))
                     :priority (or ,priority 10)
                     :dependencies ,dependencies
                     :trigger-fn ,trigger
                     :neuro-prompt ,neuro
                     :symbolic-fn ,symbolic)))

(defun find-triggered-skill (context)
  "The Skill Dispatcher. 
   Iterates over all loaded skills and returns the one with the 
   highest priority whose trigger returns true for the current context."
  (let ((triggered nil))
    (maphash (lambda (name skill)
               (declare (ignore name))
               ;; We catch errors during trigger evaluation to prevent a 
               ;; buggy skill from crashing the main cognitive loop.
               (when (ignore-errors (funcall (skill-trigger-fn skill) context))
                 (push skill triggered)))
             *skills-registry*)
    ;; Return the highest priority match.
    (first (sort triggered #'> :key #'skill-priority))))

;;; ============================================================================
;;; Secure Hot-Loading Protocol
;;; ============================================================================

(defun resolve-skill-dependencies (skill-name)
  "Recursively resolves all dependencies for a given skill. 
   Returns a flattened list of skill names in topological order."
  (let ((resolved nil)
        (seen nil))
    (labels ((visit (name)
               (unless (member name seen :test #'equal)
                 (push name seen)
                 (let ((skill (gethash (string-downcase (string name)) *skills-registry*)))
                   (when skill
                     (dolist (dep (skill-dependencies skill))
                       (visit dep))))
                 (push name resolved))))
      (visit skill-name)
      (nreverse resolved))))

(defun load-skill-from-org (filepath)
  "Parses an Org file, extracts Lisp source blocks, and hot-loads them into 
   an isolated namespace. Supports #+DEPENDS_ON: for Skill Graph construction."
  (when (uiop:file-exists-p filepath)
    (let* ((content (uiop:read-file-string filepath))
           (lines (uiop:split-string content :separator '(#\Newline)))
           (in-lisp-block nil)
           (lisp-code "")
           (dependencies nil)
           ;; We derive the package name from the filename to ensure uniqueness.
           (skill-base-name (pathname-name filepath))
           (pkg-name (intern (string-upcase (format nil "ORG-AGENT.SKILLS.~a" skill-base-name)) :keyword)))
      
      ;; PARSE HEADER: Extract dependencies
      (dolist (line lines)
        (let ((clean-line (string-trim '(#\Space #\Tab #\Return) line)))
          (when (uiop:string-prefix-p "#+DEPENDS_ON:" (string-upcase clean-line))
            (let ((deps-str (string-trim '(#\Space #\Tab) (subseq clean-line 13))))
              ;; Handle both space-separated and [[wikilink]] formats
              (setf dependencies 
                    (mapcar (lambda (s) (string-trim "[] " s))
                            (uiop:split-string deps-str :separator '(#\Space))))))))

      ;; ROBUST PARSER: Scan for tags at the start of lines, ignoring trailing text like metadata.
      (dolist (line lines)
        (let ((clean-line (string-trim '(#\Space #\Tab #\Return) line)))
          (cond
           ((uiop:string-prefix-p "#+begin_src lisp" (string-downcase clean-line)) 
            (setf in-lisp-block t))
           ((uiop:string-prefix-p "#+end_src" (string-downcase clean-line)) 
            (setf in-lisp-block nil))
           (in-lisp-block (setf lisp-code (concatenate 'string lisp-code line (string #\Newline)))))))
      
      (when (> (length lisp-code) 0)
        (kernel-log "KERNEL: Jailing Org-Native Skill '~a' (Deps: ~a) in package ~a~%" 
                    skill-base-name dependencies pkg-name)
        
        ;; DYNAMIC PACKAGE CREATION: 
        ;; We create a sandbox package that :USEs :CL and :ORG-AGENT.
        (unless (find-package pkg-name)
          (make-package pkg-name :use '(:cl :org-agent)))
        
        ;; SECURE EVALUATION:
        (let ((*read-eval* nil) ; PREVENT READ-TIME ARBITRARY CODE EXECUTION
              (*package* (find-package pkg-name)))
          ;; We wrap the code in a PROGN so multiple forms can be evaluated at once.
          (handler-case
              (eval (read-from-string (format nil "(progn ~a)" lisp-code)))
            (error (c)
              (kernel-log "READER ERROR in skill '~a': ~a~%" skill-base-name c))))))))

(defun validate-lisp-syntax (code-string)
  "Verifies that a string of Lisp code is syntactically valid.
   Does NOT execute the code. Returns (values boolean error-message)."
  (handler-case
      (let ((*read-eval* nil))
        (with-input-from-string (stream (format nil "(progn ~a)" code-string))
          (loop for form = (read stream nil :eof)
                until (eq form :eof))
          (values t nil)))
    (error (c)
      (values nil (format nil "~a" c)))))

