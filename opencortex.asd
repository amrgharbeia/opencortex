(defsystem :opencortex
  :name "opencortex"
  :author "Amr"
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
                (:file "skills/org-skill-lisp-validator")
                (:file "skills/org-skill-peripheral-vision"))

  :build-operation "program-op"
  :build-pathname "opencortex-server"
  :entry-point "opencortex:main")

(defsystem :opencortex/tests
  :depends-on (:opencortex :fiveam)
  :components ((:file "harness/act-tests")
               (:file "harness/boot-sequence-tests")
               (:file "harness/immune-system-tests")
               (:file "harness/memory-tests")
               (:file "harness/pipeline-act-tests")
               (:file "harness/pipeline-perceive-tests")
               (:file "harness/pipeline-reason-tests")
               (:file "harness/peripheral-vision-tests")
               (:file "harness/emacs-edit-tests")
               (:file "harness/engineering-standards-tests")
               (:file "harness/lisp-utils-tests")
               (:file "harness/lisp-validator-tests")
               (:file "harness/literate-programming-tests")
               (:file "harness/self-edit-tests")
               (:file "harness/tool-permissions-tests")))

(defsystem :opencortex/tui
  :depends-on (:opencortex :croatoan :usocket :bordeaux-threads)
  :components ((:file "harness/tui-client")))