(defsystem :opencortex
  :name "opencortex"
  :author "Amr Gharbeia"
  :version "0.2.0"
  :license "AGPLv3"
  :description "The Probabilistic-Deterministic Lisp Machine"
  :depends-on (:usocket :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad :str :cl-json :uuid)
  :serial t
  :components ((:file "harness/package")
               (:file "harness/skills")
               (:file "harness/communication")
               (:file "harness/communication-validator")
               (:file "harness/memory")
               (:file "harness/context")
               (:file "harness/perceive")
               (:file "harness/reason")
               (:file "harness/act")
               (:file "harness/doctor")
               (:file "harness/loop")))

(defsystem :opencortex/tests
  :depends-on (:opencortex :fiveam)
  :components ((:file "tests/pipeline-act-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/memory-tests")
               (:file "tests/pipeline-perceive-tests")
               (:file "tests/pipeline-reason-tests")
               (:file "tests/peripheral-vision-tests")
               (:file "tests/utils-org-tests")
               (:file "tests/engineering-standards-tests")
               (:file "tests/utils-lisp-tests")
               (:file "tests/literate-programming-tests")
               (:file "tests/self-edit-tests")
               (:file "tests/tool-permissions-tests")
               (:file "tests/diagnostics-tests")
               (:file "tests/config-manager-tests")
               (:file "tests/gateway-manager-tests")
               (:file "tests/tui-tests")
               (:file "tests/llm-gateway-tests")))

(defsystem :opencortex/tui
  :depends-on (:opencortex :croatoan :usocket :bordeaux-threads)
  :components ((:file "harness/tui-client")))
