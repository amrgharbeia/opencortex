(defpackage :opencortex-boot-tests
  (:use :cl :fiveam :opencortex)
  (:export #:boot-suite))

(in-package :opencortex-boot-tests)

(def-suite boot-suite :description "Verification of the Skill Engine loader")

(in-suite boot-suite)

(test test-parse-skill-metadata
  "Verify extraction of ID and DEPENDS_ON from Org headers."
  (let ((tmp-file "/tmp/org-skill-test-metadata.org"))
    (with-open-file (out tmp-file :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: test-id~%:END:~%#+DEPENDS_ON: dep1 dep2~%"))
    (unwind-protect
         (multiple-value-bind (id deps) (opencortex::parse-skill-metadata tmp-file)
           (is (equal "test-id" id))
           (is (member "dep1" deps :test #'string=))
           (is (member "dep2" deps :test #'string=)))
       (uiop:delete-file-if-exists tmp-file))))

(test test-topological-sort-basic
  "Verify that skills are ordered by dependency."
  (let ((tmp-dir "/tmp/opencortex-boot-test/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    (with-open-file (out (merge-pathnames "org-skill-a.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+DEPENDS_ON: skill-b-id~%"))
    (with-open-file (out (merge-pathnames "org-skill-b.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: skill-b-id~%:END:~%"))
    (unwind-protect
         (let ((sorted (opencortex::topological-sort-skills tmp-dir)))
           (let ((pos-a (position "org-skill-a" sorted :key #'pathname-name :test #'string-equal))
                 (pos-b (position "org-skill-b" sorted :key #'pathname-name :test #'string-equal)))
             (is (< pos-b pos-a))))
       (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t))))

(test test-skill-jailing
  "Verify that skills are loaded into their own packages."
  (let ((tmp-skill "/tmp/org-skill-jail-test.org"))
    (with-open-file (out tmp-skill :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: jail-test-id~%:END:~%#+TITLE: Jail Test Skill~%#+begin_src lisp :tangle jail-test.lisp~%(defskill :org-skill-jail-test :priority 1 :trigger (lambda (ctx) nil) :deterministic (lambda (a c) a))~%#+end_src~%"))
    (unwind-protect
         (progn
           (opencortex::load-skill-from-org tmp-skill)
           (is (not (null (gethash "org-skill-jail-test" opencortex::*skills-registry*)))))
       (uiop:delete-file-if-exists tmp-skill))))

(test test-path-traversal-guard
  "Verify that file I/O cognitive tools block path traversal escapes."
  (let* ((tool (gethash "read-file" opencortex::*cognitive-tools*))
         (guard (opencortex::cognitive-tool-guard tool)))
    ;; Set a dummy MEMEX_DIR for the test
    (setf (uiop:getenv "MEMEX_DIR") "/home/user/memex")
    
    ;; Valid internal paths should return true
    (is (not (null (funcall guard '(:file "/home/user/memex/safe.txt") nil))))
    (is (not (null (funcall guard '(:file "/home/user/memex/projects/safe.txt") nil))))
    
    ;; Path traversal escape should return false
    (is (null (funcall guard '(:file "/home/user/memex/../.bashrc") nil)))
    (is (null (funcall guard '(:file "/home/user/memex/projects/../../etc/passwd") nil)))))
