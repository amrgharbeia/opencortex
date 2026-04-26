(load "~/quicklisp/setup.lisp")

(push #p"./" asdf:*central-registry*)

(ql:quickload '(:usocket :bordeaux-threads :cl-postgres :split-sequence
                :dexador :jonathan :cl-dotenv :hunchentoot
                :trivial-garbage :s-sql :str :uuid :cl-json :uiop :fiveam))

(load "library/package.lisp")
(load "library/skills.lisp")
(load "library/communication.lisp")
(load "library/communication-validator.lisp")
(load "library/memory.lisp")
(load "library/gen/org-skill-engineering-standards.lisp")
(load "library/gen/org-skill-literate-programming.lisp")
(load "library/context.lisp")
(load "library/perceive.lisp")
(load "library/reason.lisp")
(load "library/act.lisp")
(load "library/loop.lisp")

(format t "~%=== Running ALL Test Suites ===~%")

(when (find-package :OPENCORTEX-ENGINEERING-STANDARDS-TESTS)
  (fiveam:run! 'OPENCORTEX-ENGINEERING-STANDARDS-TESTS::ENGINEERING-STANDARDS-SUITE))
(when (find-package :OPENCORTEX-LITERATE-PROGRAMMING-TESTS)
  (fiveam:run! 'OPENCORTEX-LITERATE-PROGRAMMING-TESTS::LITERATE-PROGRAMMING-SUITE))

(format t "~%=== ALL TESTS COMPLETE ===~%")