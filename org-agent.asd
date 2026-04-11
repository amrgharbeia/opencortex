(defsystem :org-agent
  :name "org-agent"
  :author "Amr"
  :version "0.1.0"
  :license "MIT"
  :description "The Neurosymbolic Lisp Machine Kernel"
  :depends-on (:usocket :cl-json :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad)
  :serial t
  :components ((:file "src/package")
               (:file "src/protocol")
               (:file "src/object-store")
               (:file "src/embedding")
               (:file "src/context")
               (:file "src/skills")
               (:file "src/neuro")
               (:file "src/symbolic")
               (:file "src/safety-harness")
               (:file "src/self-fix")
               (:file "src/lisp-repair")
               (:file "src/core"))
  :build-operation "program-op"
  :build-pathname "org-agent-server"
  :entry-point "org-agent:main")

(defsystem :org-agent/tests
  :depends-on (:org-agent :fiveam)
  :components ((:file "tests/oacp-tests")
               (:file "tests/pipeline-tests")
               (:file "tests/peripheral-vision-tests")
               (:file "tests/safety-harness-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/object-store-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/task-orchestrator-tests")
               (:file "tests/self-fix-tests")
               (:file "tests/lisp-repair-tests")
               (:file "tests/chaos-qa"))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :oacp-suite :org-agent-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :pipeline-suite :org-agent-pipeline-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :vision-suite :org-agent-peripheral-vision-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :safety-suite :org-agent-safety-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :boot-suite :org-agent-boot-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :object-store-suite :org-agent-object-store-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :immune-suite :org-agent-immune-system-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :task-orchestrator-suite :org-agent-task-orchestrator-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :self-fix-suite :org-agent-self-fix-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :lisp-repair-suite :org-agent-lisp-repair-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :chaos-suite :org-agent-chaos-qa))))
