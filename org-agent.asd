(defsystem :org-agent
  :name "org-agent"
  :author "Amr"
  :version "0.1.0"
  :license "MIT"
  :description "The Neurosymbolic Lisp Machine Kernel"
  :depends-on (:usocket :cl-json :bordeaux-threads :dexador :uiop :cl-dotenv :cl-ppcre :hunchentoot)
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "protocol")
                             (:file "object-store")
                             (:file "embedding")
                             (:file "skills")
                             (:file "neuro")
                             (:file "symbolic")
                             (:file "core"))))
  :build-operation "program-op"
  :build-pathname "org-agent-server"
  :entry-point "org-agent:main"
  :in-order-to ((test-op (test-op :org-agent/tests))))

(defsystem :org-agent/tests
  :depends-on (:org-agent :fiveam)
  :components ((:module "tests"
                :components ((:file "oacp-tests")
                             (:file "cognitive-loop-tests"))))
  :perform (test-op (o s) 
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :oacp-suite :org-agent-tests))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :cognitive-suite :org-agent-cognitive-tests))))
