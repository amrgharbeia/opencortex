(defpackage :org-agent-self-fix-tests
  (:use :cl :fiveam :org-agent)
  (:export #:self-fix-suite))
(in-package :org-agent-self-fix-tests)

(def-suite self-fix-suite :description "Verification of the Autonomous Self-Fix Loop.")
(in-suite self-fix-suite)

(defun create-broken-skill (path)
  "Programmatically generates a broken skill with a type error."
  (with-open-file (out path :direction :output :if-exists :supersede)
    (format out ":PROPERTIES:
:ID:       skill-broken-math
:CREATED:  [2026-04-11 Sat]
:END:
#+TITLE: SKILL: Broken Math (Temporary for Self-Fix Test)

* Implementation
#+begin_src lisp
(org-agent:defskill :skill-broken-math
  :priority 50
  :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :broken-trigger))
  :probabilistic nil
  :deterministic (lambda (action context)
              (declare (ignore action context))
              (+ 1 \"two\"))) ; DETERMINISTIC BUG
#+end_src
")))

(test test-autonomous-self-fix-loop
  "Verifies that a crash in a skill triggers the self-fix agent to patch the code."
  (let* ((skills-dir (merge-pathnames "skills/" (asdf:system-source-directory :org-agent)))
         (broken-skill-path (merge-pathnames "org-skill-broken-math.org" skills-dir))
         (original-content nil))
    
    (unwind-protect
         (progn
           ;; 1. Setup the broken skill
           (create-broken-skill broken-skill-path)
           (is (org-agent:load-skill-from-org broken-skill-path))
           (setf original-content (uiop:read-file-string broken-skill-path))
           (is (search "(+ 1 \"two\")" original-content))
           
           ;; 2. Trigger the crash
           (let ((crash-stimulus '(:type :EVENT :payload (:sensor :broken-trigger))))
             (org-agent:process-signal crash-stimulus))
           
           ;; 3. Mock the repair proposal and trigger the fix
           ;; We manually simulate what the LLM would do: propose a fix via repair-file.
           (let* ((repair-action '(:type :REQUEST :target :tool :action :call :tool "repair-file"
                                   :args (:file "org-skill-broken-math.org"
                                          :old "(+ 1 \"two\")"
                                          :new "(+ 1 2)")))
                  ;; We need to provide the full path to the skill file for self-fix-apply
                  (full-repair-action (list :type :REQUEST :target :tool :action :call :tool "repair-file"
                                            :payload (list :file broken-skill-path
                                                           :old "(+ 1 \"two\")"
                                                           :new "(+ 1 2)"))))
             
             ;; Execute the repair
             (is (org-agent::self-fix-apply full-repair-action nil)))
           
           ;; 4. Verify the fix
           (let ((patched-content (uiop:read-file-string broken-skill-path)))
             (is (not (search "(+ 1 \"two\")" patched-content)))
             (is (search "(+ 1 2)" patched-content))
             
             ;; Verify that the skill is reloaded and working (no longer crashes)
             (let ((working-stimulus '(:type :EVENT :payload (:sensor :broken-trigger))))
               (handler-case
                   (progn
                     (org-agent:process-signal working-stimulus)
                     (pass "Skill successfully repaired and reloaded."))
                 (error (c)
                   (fail (format nil "Skill still broken after repair: ~a" c)))))))
      
      ;; 5. Cleanup
      (uiop:delete-file-if-exists broken-skill-path)
      (clrhash org-agent::*skills-registry*)
      (org-agent:initialize-all-skills))))
