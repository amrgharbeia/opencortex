(defsystem :org-agent
  :name "org-agent"
  :author "Amr"
  :version "0.1.0"
  :license "MIT"
  :description "The Neurosymbolic Lisp Machine Kernel"
  :depends-on (:usocket :cl-json :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot :ironclad)
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "protocol")
                             (:file "object-store")
                             (:file "embedding")
                             (:file "context")
                             (:file "skills")
                             (:file "neuro")
                             (:file "symbolic")
                             (:file "safety-harness")
                             (:file "core"))))
  :build-operation "program-op"
  :build-pathname "org-agent-server"
  :entry-point "org-agent:main"
  :in-order-to ((test-op (test-op :org-agent/tests))))

(defsystem :org-agent/tests
  :depends-on (:org-agent :fiveam)
  :components ((:module "tests"
                :components ((:file "oacp-tests")
                             (:file "pipeline-tests")
                             (:file "peripheral-vision-tests")
                             (:file "safety-harness-tests")
                             (:file "boot-sequence-tests")
                             (:file "object-store-tests")
                             (:file "immune-system-tests")
                             (:file "chaos-qa"))))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :oacp-suite :org-agent-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :pipeline-suite :org-agent-pipeline-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :vision-suite :org-agent-peripheral-vision-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :safety-suite :org-agent-safety-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :boot-suite :org-agent-boot-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :object-store-suite :org-agent-object-store-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :immune-suite :org-agent-immune-system-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :chaos-suite :org-agent-chaos-qa))))
