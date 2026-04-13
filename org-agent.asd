(defsystem :org-agent
  :name "org-agent"
  :author "Amr"
  :version "0.1.0"
  :license "MIT"
  :description "The Metabolic Neurosymbolic Lisp Machine"
  :depends-on (:usocket :cl-json :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad :str)
  :serial t
  :components ((:file "src/package")
               (:file "src/skills")
               (:file "src/engineering-standards")
               (:file "src/protocol-validator")
               (:file "src/protocol")
               ;; --- Memory Layer ---
               (:file "src/object-store")
               (:file "src/homoiconic-memory")
               (:file "src/state-persistence")
               (:file "src/embedding")
               (:file "src/embedding-logic")
               (:file "src/context")
               (:file "src/context-logic")
               ;; --- Metabolic Harness ---
               (:file "src/perceive")
               (:file "src/reason")
               (:file "src/act")
               (:file "src/loop")
               ;; --- Core Mandatory Skills ---
               (:file "src/policy-enforcer")
               (:file "src/lisp-validator")
               (:file "src/harness-monitor")
               (:file "src/llm-gateway")
               (:file "src/credentials-vault")
               (:file "src/chat-logic")
               (:file "src/self-fix")
               (:file "src/lisp-repair")
               ;; --- Gateways ---
               (:file "src/gateway-telegram")
               (:file "src/gateway-signal")
               (:file "src/gateway-matrix"))
  :build-operation "program-op"
  :build-pathname "org-agent-server"
  :entry-point "org-agent:main")

(defsystem :org-agent/tests
  :depends-on (:org-agent :fiveam)
  :components ((:file "tests/protocol-tests")
               (:file "tests/pipeline-tests")
               (:file "tests/peripheral-vision-tests")
               (:file "tests/lisp-validator-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/object-store-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/task-orchestrator-tests")
               (:file "tests/self-fix-tests")
               (:file "tests/lisp-repair-tests")
               (:file "tests/bouncer-tests")
               (:file "tests/formal-verification-tests")
               (:file "tests/llm-gateway-tests")
               (:file "tests/gateway-telegram-tests")
               (:file "tests/gateway-signal-tests")
               (:file "tests/gateway-matrix-tests"))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :harness-protocol-suite :org-agent-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :pipeline-suite :org-agent-pipeline-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :vision-suite :org-agent-peripheral-vision-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :lisp-validator-suite :org-agent-lisp-validator-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :boot-suite :org-agent-boot-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :object-store-suite :org-agent-object-store-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :immune-suite :org-agent-immune-system-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :task-orchestrator-suite :org-agent-task-orchestrator-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :self-fix-suite :org-agent-self-fix-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :lisp-repair-suite :org-agent-lisp-repair-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :bouncer-suite :org-agent-bouncer-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :formal-verification-suite :org-agent-formal-verification-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :llm-gateway-suite :org-agent-llm-gateway-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :gateway-telegram-suite :org-agent-gateway-telegram-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :gateway-signal-suite :org-agent-gateway-signal-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :gateway-matrix-suite :org-agent-gateway-matrix-tests))))
