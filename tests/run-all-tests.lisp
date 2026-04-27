(load "~/quicklisp/setup.lisp")

(push #p"./" asdf:*central-registry*)

(ql:quickload '(:usocket :bordeaux-threads :cl-postgres :split-sequence
                :dexador :jonathan :cl-dotenv :hunchentoot
                :trivial-garbage :s-sql :str :uuid :cl-json :uiop :fiveam))

(asdf:load-system :opencortex)
(asdf:load-system :opencortex/tests)

(format t "~%=== Running ALL Test Suites ===~%")

;; Engineering Standards tests
(when (find-package :OPENCORTEX-ENGINEERING-STANDARDS-TESTS)
  (fiveam:run! 'OPENCORTEX-ENGINEERING-STANDARDS-TESTS::ENGINEERING-STANDARDS-SUITE))

;; Literate Programming tests
(when (find-package :OPENCORTEX-LITERATE-PROGRAMMING-TESTS)
  (fiveam:run! 'OPENCORTEX-LITERATE-PROGRAMMING-TESTS::LITERATE-PROGRAMMING-SUITE))

;; Communication tests
(when (find-package :OPENCORTEX-TESTS)
  (fiveam:run! 'OPENCORTEX-TESTS::COMMUNICATION-PROTOCOL-SUITE))

;; Pipeline tests
(when (find-package :OPENCORTEX-PIPELINE-TESTS)
  (fiveam:run! 'OPENCORTEX-PIPELINE-TESTS::PIPELINE-SUITE))

;; Boot sequence tests
(when (find-package :OPENCORTEX-BOOT-TESTS)
  (fiveam:run! 'OPENCORTEX-BOOT-TESTS::BOOT-SUITE))

;; Memory tests
(when (find-package :OPENCORTEX-MEMORY-TESTS)
  (fiveam:run! 'OPENCORTEX-MEMORY-TESTS::MEMORY-SUITE))

;; Immune system tests
(when (find-package :OPENCORTEX-IMMUNE-SYSTEM-TESTS)
  (fiveam:run! 'OPENCORTEX-IMMUNE-SYSTEM-TESTS::IMMUNE-SUITE))

;; Emacs edit tests
(when (find-package :OPENCORTEX-EMACS-EDIT-TESTS)
  (fiveam:run! 'OPENCORTEX-EMACS-EDIT-TESTS::EMACS-EDIT-SUITE))

;; Lisp utils tests
(when (find-package :OPENCORTEX-LISP-UTILS-TESTS)
  (fiveam:run! 'OPENCORTEX-LISP-UTILS-TESTS::LISP-UTILS-SUITE))

(format t "~%=== ALL TESTS COMPLETE ===~%")
