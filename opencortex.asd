(defsystem :opencortex
  :name "opencortex"
  :author "Amr"
  :version "0.1.0"
  :license "AGPLv3"
  :description "The Probabilistic-Deterministic Lisp Machine Harness"
  :depends-on (:usocket :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad :str :cl-json :uuid)
  :serial t
  :components ((:file "library/package")
               (:file "library/skills")
               (:file "library/communication")
               (:file "library/memory")
               (:file "library/context")
               (:file "library/perceive")
               (:file "library/reason")
               (:file "library/act")
               (:file "library/loop"))
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
               (:file "tests/immune-system-tests"))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :communication-protocol-suite :opencortex-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :pipeline-suite :opencortex-pipeline-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :safety-suite :opencortex-safety-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :boot-suite :opencortex-boot-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :memory-suite :opencortex-memory-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :immune-suite :opencortex-immune-system-tests))))

(defsystem :opencortex/tui
  :depends-on (:opencortex :croatoan :usocket :bordeaux-threads)
  :components ((:file "library/tui-client")))
