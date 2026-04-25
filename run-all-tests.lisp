(load "/home/user/quicklisp/setup.lisp")
(push #p"./" asdf:*central-registry*)
(ql:quickload :fiveam :verbose nil)
(asdf:load-system :opencortex/tests :verbose nil)

;; Load tool permissions skill
(load "library/gen/org-skill-tool-permissions.lisp")
(load "tests/tool-permissions-tests.lisp")

(format t "~%=== Running ALL Test Suites ===~%")

(fiveam:run! 'opencortex-tests::communication-protocol-suite)
(fiveam:run! 'opencortex-pipeline-tests::pipeline-suite)
(fiveam:run! 'opencortex-boot-tests::boot-suite)
(fiveam:run! 'opencortex-memory-tests::memory-suite)
(fiveam:run! 'opencortex-immune-system-tests::immune-suite)
(fiveam:run! 'opencortex-emacs-edit-tests::emacs-edit-suite)
(fiveam:run! 'opencortex-lisp-utils-tests::lisp-utils-suite)
(fiveam:run! 'opencortex-tool-permissions-tests::tool-permissions-suite)

(format t "~%=== ALL TESTS COMPLETE ===~%")