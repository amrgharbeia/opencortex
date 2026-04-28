(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

(let ((oc-dir (or (uiop:getenv "OC_DATA_DIR") 
                  (namestring (truename "./")))))
  (push (uiop:ensure-directory-pathname oc-dir) asdf:*central-registry*))

(progn
  (ql:quickload :opencortex :silent t)
  (finish-output))

(format t "~%=== Initializing Skills BEFORE loading tests ===~%")
(finish-output)
(opencortex:initialize-all-skills)

(format t "~%=== Loading Test System ===~%")
(finish-output)
(progn
  (ql:quickload :opencortex/tests :silent t)
  (finish-output))

(format t "~%=== Running ALL Test Suites ===~%")
(finish-output)

(let ((suites '(("ENGINEERING-STANDARDS" . "OPENCORTEX-ENGINEERING-STANDARDS-TESTS::ENGINEERING-STANDARDS-SUITE")
                ("LITERATE-PROGRAMMING" . "OPENCORTEX-LITERATE-PROGRAMMING-TESTS::LITERATE-PROGRAMMING-SUITE")
                ("COMMUNICATION" . "OPENCORTEX-COMMUNICATION-TESTS::COMMUNICATION-PROTOCOL-SUITE")
                ("PIPELINE" . "OPENCORTEX-PIPELINE-TESTS::PIPELINE-SUITE")
                ("BOOT" . "OPENCORTEX-BOOT-TESTS::BOOT-SUITE")
                ("MEMORY" . "OPENCORTEX-MEMORY-TESTS::MEMORY-SUITE")
                ("IMMUNE" . "OPENCORTEX-IMMUNE-SYSTEM-TESTS::IMMUNE-SUITE")
                ("EMACS-EDIT" . "OPENCORTEX-EMACS-EDIT-TESTS::EMACS-EDIT-SUITE")
                ("LISP-UTILS" . "OPENCORTEX-LISP-UTILS-TESTS::LISP-UTILS-SUITE")
                ("SELF-EDIT" . "OPENCORTEX-SELF-EDIT-TESTS::SELF-EDIT-SUITE")
                ("TOOL-PERMISSIONS" . "OPENCORTEX-TOOL-PERMISSIONS-TESTS::TOOL-PERMISSIONS-SUITE")
                ("CONFIG" . "OPENCORTEX-CONFIG-MANAGER-TESTS::CONFIG-SUITE")
                ("DIAGNOSTICS" . "OPENCORTEX-DIAGNOSTICS-TESTS::DIAGNOSTICS-SUITE"))))
  (dolist (suite suites)
    (let ((pkg (intern (string-upcase (car (uiop:split-string (cdr suite) :separator "::"))) :keyword)))
      (when (find-package pkg)
        (format t "~&--- Suite: ~A ---~%" (car suite))
        (fiveam:run! (uiop:safe-read-from-string (cdr suite)))))))

(format t "~%=== ALL TESTS COMPLETE ===~%")
