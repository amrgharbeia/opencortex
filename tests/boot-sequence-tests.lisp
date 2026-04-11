(defpackage :org-agent-boot-tests
  (:use :cl :fiveam :org-agent)
  (:export #:boot-suite))
(in-package :org-agent-boot-tests)

(def-suite boot-suite :description "Verification of the Micro-Loader.")
(in-suite boot-suite)

(test test-parse-skill-metadata
  "Verify extraction of ID and DEPENDS_ON from Org headers."
  (let ((tmp-file "/tmp/org-skill-test-metadata.org"))
    (with-open-file (out tmp-file :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: test-id~%:END:~%#+DEPENDS_ON: dep1 dep2~%"))
    (unwind-protect
         (multiple-value-bind (id deps) (org-agent::parse-skill-metadata tmp-file)
           (is (equal "test-id" id))
           (is (member "dep1" deps :test #'string=))
           (is (member "dep2" deps :test #'string=)))
      (uiop:delete-file-if-exists tmp-file))))

(test test-topological-sort-basic
  "Verify that skills are ordered by dependency."
  (let ((tmp-dir "/tmp/org-agent-boot-test/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    ;; A depends on B
    (with-open-file (out (merge-pathnames "org-skill-a.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+DEPENDS_ON: id:skill-b-id~%"))
    (with-open-file (out (merge-pathnames "org-skill-b.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out ":PROPERTIES:~%:ID: skill-b-id~%:END:~%"))
    ;; Add executive soul (required)
    (with-open-file (out (merge-pathnames "org-skill-agent.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+TITLE: Agent~%"))
    
    (unwind-protect
         (let ((sorted (org-agent::topological-sort-skills tmp-dir)))
           ;; B must appear before A
           (let ((pos-a (position "org-skill-a" sorted :key #'pathname-name :test #'string-equal))
                 (pos-b (position "org-skill-b" sorted :key #'pathname-name :test #'string-equal)))
             (is (not (null pos-a)))
             (is (not (null pos-b)))
             (is (< pos-b pos-a))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t))))

(test test-topological-sort-circular
  "Verify that circular dependencies raise an error."
  (let ((tmp-dir "/tmp/org-agent-boot-test-circ/"))
    (uiop:ensure-all-directories-exist (list tmp-dir))
    ;; A depends on B, B depends on A
    (with-open-file (out (merge-pathnames "org-skill-a.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+DEPENDS_ON: org-skill-b~%"))
    (with-open-file (out (merge-pathnames "org-skill-b.org" tmp-dir) :direction :output :if-exists :supersede)
      (format out "#+DEPENDS_ON: org-skill-a~%"))
    
    (unwind-protect
         (signals error (org-agent::topological-sort-skills tmp-dir))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname tmp-dir) :validate t))))

(test test-skill-jailing
  "Verify that skills are loaded into their own packages."
  (let ((tmp-skill "/tmp/org-skill-jail-test.org"))
    (with-open-file (out tmp-skill :direction :output :if-exists :supersede)
      (format out "#+begin_src lisp~%(defvar *jailed-var* 42)~%#+end_src"))
    (unwind-protect
         (progn
           (org-agent::load-skill-from-org tmp-skill)
           (let ((pkg (find-package :ORG-AGENT.SKILLS.ORG-SKILL-JAIL-TEST)))
             (is (not (null pkg)))
             (is (= 42 (symbol-value (find-symbol "*JAILED-VAR*" pkg))))))
      (uiop:delete-file-if-exists tmp-skill))))

(test test-syntax-validation
  "Verify that malformed Lisp is caught by the pre-flight check."
  (is (nth-value 0 (org-agent::validate-lisp-syntax "(defun x () t)")))
  (is (not (nth-value 0 (org-agent::validate-lisp-syntax "(defun x (")))))
