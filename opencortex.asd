(defsystem :opencortex
  :name "opencortex"
  :author "Amr"
  :version "0.1.0"
  :license "AGPLv3"
  :description "The Probabilistic-Deterministic Lisp Machine Harness"

  :depends-on (:usocket              ; TCP socket networking
               :bordeaux-threads     ; Threading (heartbeat, async sensors)
               :dexador              ; HTTP client (LLM APIs)
               :uiop                 ; Portable I/O, file operations
               :cl-dotenv            ; Environment variable loading
               :cl-ppcre             ; Regular expressions (parsing)
               :hunchentoot          ; HTTP server (optional web interface)
               :ironclad             ; Cryptography (Merkle hashing)
               :str                  ; String utilities
               :cl-json              ; JSON parsing/serialization
               :uuid)                ; UUID generation for org-mode IDs

  :serial t                          ; Load files in order listed below

:components ((:file "library/package")           ; Package definitions, core vars
               (:file "library/skills")            ; Skill engine, cognitive tools
               (:file "library/communication")     ; Protocol, framing
               (:file "library/communication-validator") ; Schema validation
               (:file "library/memory")            ; Org-object store, snapshots
               (:file "library/gen/org-skill-engineering-standards") ; Enforcement
               (:file "library/gen/org-skill-literate-programming") ; LP enforcement
               (:file "library/context")           ; Context assembly, query
               (:file "library/perceive")         ; Stage 1: Sensory normalization
               (:file "library/reason")           ; Stage 2: Neural + deterministic
               (:file "library/act")               ; Stage 3: Actuation
               (:file "library/loop"))             ; Main entry, heartbeat

  :build-operation "program-op"
  :build-pathname "opencortex-server"
  :entry-point "opencortex:main")

(defsystem :opencortex/tests
  :depends-on (:opencortex           ; The harness we're testing
               :fiveam)              ; Testing framework

:components ((:file "library/gen/org-skill-emacs-edit")
               (:file "library/gen/org-skill-lisp-utils")
               (:file "library/gen/org-skill-tool-permissions")
               (:file "tests/communication-tests")
               (:file "tests/pipeline-tests")
               (:file "tests/act-tests")
               (:file "tests/boot-sequence-tests")
               (:file "tests/memory-tests")
               (:file "tests/immune-system-tests")
               (:file "tests/emacs-edit-tests")
               (:file "tests/lisp-utils-tests")
               (:file "tests/tool-permissions-tests")
               (:file "tests/engineering-standards-tests")
               (:file "tests/literate-programming-tests"))

  :perform (test-op (o s)
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :communication-protocol-suite :opencortex-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :pipeline-suite :opencortex-pipeline-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :boot-suite :opencortex-boot-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :memory-suite :opencortex-memory-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :immune-suite :opencortex-immune-system-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :emacs-edit-suite :opencortex-emacs-edit-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :lisp-utils-suite :opencortex-lisp-utils-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :engineering-standards-suite :opencortex-engineering-standards-tests))
    (uiop:symbol-call :fiveam :run!
      (uiop:find-symbol* :literate-programming-suite :opencortex-literate-programming-tests))))

(defsystem :opencortex/tui
  :depends-on (:opencortex           ; The daemon we're connecting to
               :croatoan            ; Terminal UI library
               :usocket              ; Socket communication
               :bordeaux-threads)    ; Background listening thread

  :components ((:file "library/tui-client")))
