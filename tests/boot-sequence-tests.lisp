(defpackage :org-agent-boot-tests
  (:use :cl :fiveam :org-agent))
(in-package :org-agent-boot-tests)

(def-suite boot-suite
  :description "Verification of the Topological Boot Sequence.")
(in-suite boot-suite)

(defun call-with-temp-dir (fn)
  (let ((tmp-dir (uiop:ensure-directory-pathname 
                  (string-right-trim '(#\Newline) 
                                     (uiop:run-program "mktemp -d" :output :string)))))
    (unwind-protect
         (funcall fn tmp-dir)
      (uiop:delete-directory-tree tmp-dir :validate t))))

(test gateway-enforcement
  "Prove failure if org-skill-agent.org is missing."
  (call-with-temp-dir 
   (lambda (tmp-dir)
     (let ((old-skills (uiop:getenv "SKILLS_DIR")))
       (setf (uiop:getenv "SKILLS_DIR") (namestring tmp-dir))
       (unwind-protect
            (signals error (org-agent::load-all-skills))
         (when old-skills (setf (uiop:getenv "SKILLS_DIR") old-skills)))))))

(test topological-sort-logic
  "Verify that skills are sorted based on #+DEPENDS_ON tags."
  (call-with-temp-dir
   (lambda (tmp-dir)
     (let ((file-a (merge-pathnames "org-skill-a.org" tmp-dir))
           (file-b (merge-pathnames "org-skill-b.org" tmp-dir))
           (file-c (merge-pathnames "org-skill-c.org" tmp-dir)))
       ;; A depends on B, B depends on C. Final order should be C, B, A.
       (alexandria:write-string-into-file "#+TITLE: Skill A\n#+DEPENDS_ON: id:org-skill-b" file-a)
       (alexandria:write-string-into-file "#+TITLE: Skill B\n#+DEPENDS_ON: id:org-skill-c" file-b)
       (alexandria:write-string-into-file "#+TITLE: Skill C" file-c)
       
       (let ((sorted (org-agent:topological-sort-skills tmp-dir)))
         (is (equal "org-skill-c" (pathname-name (first sorted))))
         (is (equal "org-skill-b" (pathname-name (second sorted))))
         (is (equal "org-skill-a" (pathname-name (third sorted)))))))))

(test circular-dependency
  "Verify that circular dependencies signal an error."
  (call-with-temp-dir
   (lambda (tmp-dir)
     (let ((file-a (merge-pathnames "org-skill-a.org" tmp-dir))
           (file-b (merge-pathnames "org-skill-b.org" tmp-dir)))
       (alexandria:write-string-into-file "#+DEPENDS_ON: id:org-skill-b" file-a)
       (alexandria:write-string-into-file "#+DEPENDS_ON: id:org-skill-a" file-b)
       (signals error (org-agent:topological-sort-skills tmp-dir))))))

(test load-skill-timeout
  "Verify that slow skills are terminated."
  (call-with-temp-dir
   (lambda (tmp-dir)
     (let ((slow-file (merge-pathnames "org-skill-slow.org" tmp-dir)))
       (alexandria:write-string-into-file "#+begin_src lisp\n(sleep 10)\n#+end_src" slow-file)
       (is (eq :timeout (org-agent:load-skill-with-timeout slow-file 1)))))))
