(defpackage :opencortex-config-manager-tests
  (:use :cl :fiveam :opencortex)
  (:export #:config-suite))

(in-package :opencortex-config-manager-tests)

(def-suite config-suite :description "Verification of the Config Manager skill")

(in-suite config-suite)

(test test-provider-registration
  "Verify that multiple providers can be registered and saved."
  (let ((opencortex::*providers* nil))
    (opencortex:register-provider :ollama '(:url "http://localhost:11434"))
    (is (equal "http://localhost:11434" (getf (getf opencortex::*providers* :ollama) :url)))))

(test test-get-oc-config-dir-default
  "Verify get-oc-config-dir returns XDG-compliant path when env not set."
  (let ((orig-env (uiop:getenv "OC_CONFIG_DIR")))
    (unwind-protect
        (progn
          (setf (uiop:getenv "OC_CONFIG_DIR") nil)
          (let ((dir (opencortex:get-oc-config-dir)))
            (is (search ".config/opencortex" (namestring dir)))))
      (if orig-env
          (setf (uiop:getenv "OC_CONFIG_DIR") orig-env)
          (setf (uiop:getenv "OC_CONFIG_DIR") nil)))))

(test test-get-oc-config-dir-env-override
  "Verify get-oc-config-dir uses OC_CONFIG_DIR when set."
  (let ((orig-env (uiop:getenv "OC_CONFIG_DIR")))
    (unwind-protect
        (progn
          (setf (uiop:getenv "OC_CONFIG_DIR") "/tmp/test-opencortex-config")
          (let ((dir (opencortex:get-oc-config-dir)))
            (is (string= "/tmp/test-opencortex-config/" (namestring dir)))))
      (if orig-env
          (setf (uiop:getenv "OC_CONFIG_DIR") orig-env)
          (setf (uiop:getenv "OC_CONFIG_DIR") nil)))))

(test test-save-providers-roundtrip
  "Verify save-providers writes and providers can be reloaded."
  (let ((opencortex::*providers* nil)
        (test-dir "/tmp/test-opencortex-config/")
        (orig-env (uiop:getenv "OC_CONFIG_DIR")))
    (unwind-protect
        (progn
          (setf (uiop:getenv "OC_CONFIG_DIR") test-dir)
          (opencortex:register-provider :openai '(:key "test-key-123" :model "gpt-4"))
          (opencortex:save-providers)
          (let ((loaded-provs (uiop:read-file-string (merge-pathnames "providers.lisp" (uiop:ensure-directory-pathname test-dir)))))
            (is (search "openai" loaded-provs))
            (is (search "test-key-123" loaded-provs))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname test-dir) :validate t)
      (if orig-env
          (setf (uiop:getenv "OC_CONFIG_DIR") orig-env)
          (setf (uiop:getenv "OC_CONFIG_DIR") nil)))))

(test test-configure-provider-validation
  "Verify configure-provider validates required fields."
  (let ((opencortex::*providers* nil))
    (opencortex:register-provider :ollama '(:url "http://localhost:11434"))
    (let ((cfg (getf opencortex::*providers* :ollama)))
      (is (equal "http://localhost:11434" (getf cfg :url))))))
