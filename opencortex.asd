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
                (:file "harness/loop")
                (:file "harness/doctor")
                (:file "harness/setup-wizard")

                (:file "skills/org-skill-policy")
                (:file "skills/org-skill-bouncer")
                (:file "skills/org-skill-scribe")
                (:file "skills/org-skill-gardener")
                (:file "skills/org-skill-lisp-utils")
                (:file "skills/org-skill-literate-programming")
                (:file "skills/org-skill-engineering-standards")
                (:file "skills/org-skill-self-edit")
                (:file "skills/org-skill-emacs-edit")
                (:file "skills/org-skill-tool-permissions")
                (:file "skills/org-skill-self-fix")
                (:file "skills/org-skill-peripheral-vision"))

  :build-operation "program-op"
  :build-pathname "opencortex-server"
  :entry-point "opencortex:main")

(defsystem :opencortex/tests
  :depends-on (:opencortex :fiveam)
  :components ((:file "tests/pipeline-act-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/memory-tests")
               (:file "tests/pipeline-perceive-tests")
               (:file "tests/pipeline-reason-tests")
               (:file "tests/peripheral-vision-tests")
               (:file "tests/emacs-edit-tests")
               (:file "tests/engineering-standards-tests")
               (:file "tests/lisp-utils-tests")
               (:file "tests/lisp-validator-tests")
               (:file "tests/literate-programming-tests")
               (:file "tests/self-edit-tests")
               (:file "tests/tool-permissions-tests")
               (:file "tests/doctor-tests")
               (:file "tests/setup-wizard-tests")))

(defsystem :opencortex/tui
  :depends-on (:opencortex :croatoan :usocket :bordeaux-threads)
  :components ((:file "harness/tui-client")))
