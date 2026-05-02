(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))

(let ((oc-dir (or (uiop:getenv "OC_DATA_DIR")
                  (namestring (truename "./")))))
  (push (uiop:ensure-directory-pathname oc-dir) asdf:*central-registry*)
  (setf (uiop:getenv "OC_DATA_DIR") oc-dir))

(ql:quickload '(:fiveam :opencortex :opencortex/tui :opencortex/tests) :silent t)

(format t "~%=== Initializing Skills BEFORE running tests ===~%")
(opencortex:initialize-all-skills)

(format t "~%=== Running ALL Test Suites ===~%")

(dolist (suite-spec '(("OPENCORTEX-BOOT-TESTS" "BOOT-SUITE")
                      ("OPENCORTEX-COMMUNICATION-TESTS" "COMMUNICATION-PROTOCOL-SUITE")
                      ("OPENCORTEX-DOCTOR-TESTS" "DOCTOR-SUITE")
                      ("OPENCORTEX-IMMUNE-SYSTEM-TESTS" "IMMUNE-SUITE")
                      ("OPENCORTEX-LLM-GATEWAY-TESTS" "LLM-GATEWAY-SUITE")
                      ("OPENCORTEX-MEMORY-TESTS" "MEMORY-SUITE")
                      ("OPENCORTEX-PERIPHERAL-VISION-TESTS" "VISION-SUITE")
                      ("OPENCORTEX-PIPELINE-ACT-TESTS" "PIPELINE-ACT-SUITE")
                      ("OPENCORTEX-PIPELINE-PERCEIVE-TESTS" "PIPELINE-PERCEIVE-SUITE")
                      ("OPENCORTEX-PIPELINE-REASON-TESTS" "PIPELINE-REASON-SUITE")
                      ("OPENCORTEX-TUI-TESTS" "TUI-SUITE")
                      ("OPENCORTEX-UTILS-LISP-TESTS" "UTILS-LISP-SUITE")
                      ("OPENCORTEX-UTILS-ORG-TESTS" "UTILS-ORG-SUITE")))
  (let ((pkg (find-package (first suite-spec))))
    (when pkg
      (let ((suite-sym (find-symbol (second suite-spec) pkg)))
        (when suite-sym
          (format t "~&--- Suite: ~A ---~%" (first suite-spec))
          (fiveam:run! suite-sym))))))

(format t "~%=== ALL TESTS COMPLETE ===~%")
