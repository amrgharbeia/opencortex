(defsystem :opencortex
  :name "opencortex"
  :author "Amr"
  :version "0.1.0"
  :license "AGPLv3"
  :description "The Probabilistic-Deterministic Lisp Machine Harness"
  :depends-on (:usocket :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad :str :cl-json :uuid)
  :serial t
  :components ((:file "library/package")
               (:file "library/skills" :depends-on ("library/package"))
               (:file "library/memory" :depends-on ("library/package"))
               (:file "library/context" :depends-on ("library/package" "library/memory"))
               (:file "library/communication" :depends-on ("library/package"))
               (:file "library/communication-validator" :depends-on ("library/package" "library/communication"))
               (:file "library/perceive" :depends-on ("library/package"))
               (:file "library/reason" :depends-on ("library/package" "library/perceive"))
               (:file "library/act" :depends-on ("library/package" "library/reason"))
               (:file "library/loop" :depends-on ("library/package" "library/act")))
  :build-operation "program-op"
  :build-pathname "opencortex-server"
  :entry-point "opencortex:main")

(defsystem :opencortex/tests
  :depends-on (:opencortex :fiveam)
  :components ((:file "tests/communication-tests")
               (:file "tests/pipeline-tests")
               (:file "tests/act-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/memory-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/emacs-edit-tests")
               (:file "tests/lisp-utils-tests"))
  :perform (test-op (o s)
              (uiop:symbol-call :fiveam :run! :communication-protocol-suite)
              (uiop:symbol-call :fiveam :run! :pipeline-suite)
              (uiop:symbol-call :fiveam :run! :safety-suite)
              (uiop:symbol-call :fiveam :run! :boot-suite)
              (uiop:symbol-call :fiveam :run! :memory-suite)
              (uiop:symbol-call :fiveam :run! :immune-suite)
              (uiop:symbol-call :fiveam :run! :emacs-edit-suite)
              (uiop:symbol-call :fiveam :run! :lisp-utils-suite)))

(defsystem opencortex-test
  :depends-on (:opencortex/tests)
  :perform (test-op (o s) (asdf:test-system :opencortex/tests)))

(defsystem :opencortex/tui
  :depends-on (:opencortex :croatoan :usocket :bordeaux-threads)
  :components ((:file "library/tui-client")))