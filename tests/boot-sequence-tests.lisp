(defpackage :org-agent-boot-tests
  (:use :cl :fiveam :org-agent)
  (:export #:boot-suite))
(in-package :org-agent-boot-tests)

(def-suite boot-suite :description "Verification of the Micro-Loader.")
(in-suite boot-suite)

(test test-skill-catalog-tracking
  "Verify that skills are added to the catalog with correct status."
  (clrhash org-agent::*skill-catalog*)
  ;; We need a temporary skill file to test loading
  (let ((tmp-skill "/tmp/org-skill-test-catalog.org"))
    (with-open-file (out tmp-skill :direction :output :if-exists :supersede)
      (format out "#+TITLE: Test Skill~%#+begin_src lisp~%(defun test-catalog-fn () t)~%#+end_src"))
    
    (org-agent:load-skill-from-org tmp-skill)
    (let ((entry (gethash "org-skill-test-catalog" org-agent::*skill-catalog*)))
      (is (not (null entry)))
      (is (eq :ready (org-agent::skill-entry-status entry))))
    (uiop:delete-file-if-exists tmp-skill)))

(test test-syntax-preflight-blocking
  "Verify that malformed Lisp prevents skill from loading."
  (clrhash org-agent::*skill-catalog*)
  (let ((bad-skill "/tmp/org-skill-bad-syntax.org"))
    (with-open-file (out bad-skill :direction :output :if-exists :supersede)
      (format out "#+TITLE: Bad Skill~%#+begin_src lisp~%(defun unclosed (x~%#+end_src"))
    
    (org-agent:load-skill-from-org bad-skill)
    (let ((entry (gethash "org-skill-bad-syntax" org-agent::*skill-catalog*)))
      (is (eq :failed (org-agent::skill-entry-status entry)))
      (is (search "Syntax Error" (org-agent::skill-entry-error-log entry))))
    (uiop:delete-file-if-exists bad-skill)))
