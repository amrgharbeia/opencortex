(defsystem :org-agent
  :name "org-agent"
  :author "Amr"
  :version "0.1.0"
  :license "MIT"
  :description "The Probabilistic-Deterministic Lisp Machine Harness"
  :depends-on (:usocket ::bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad :str :cl-json)
  :serial t
  :components ((:file "src/package")
               (:file "src/skills")
               (:file "src/system-invariants")
               (:file "src/engineering-standards")
               (:file "src/communication-validator")
               (:file "src/communication")
               (:file "src/memory")
               (:file "src/context")
               (:file "src/probabilistic")
               (:file "src/deterministic")
               (:file "src/loop"))
  :build-operation "program-op"
  :build-pathname "org-agent-server"
  :entry-point "org-agent:main")

(defsystem :org-agent/tests
  :depends-on (:org-agent :fiveam)
  :components ((:file "tests/communication-tests")
               (:file "tests/pipeline-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/memory-tests")
               (:file "tests/immune-system-tests"))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :communication-protocol-suite :org-agent-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :pipeline-suite :org-agent-pipeline-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :safety-suite :org-agent-safety-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :boot-suite :org-agent-boot-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :memory-suite :org-agent-memory-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :immune-suite :org-agent-immune-system-tests))))
