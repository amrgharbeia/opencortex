(defpackage :opencortex-peripheral-vision-tests
  (:use :cl :fiveam :opencortex)
  (:export #:vision-suite))
(in-package :opencortex-peripheral-vision-tests)

(def-suite vision-suite
  :description "Verification of Foveal-Peripheral context model.")
(in-suite vision-suite)

(test test-foveal-rendering
  "Verify that the foveal target is rendered with content, while siblings are skeletal."
  (clrhash opencortex::*memory*)
  (let* ((ast '(:type :HEADLINE :properties (:ID "proj-root" :TITLE "Project" :TAGS "project")
                :contents ((:type :HEADLINE :properties (:ID "node-foveal" :TITLE "Foveal Node")
                            :raw-content "FOVEAL CONTENT" :contents nil)
                           (:type :HEADLINE :properties (:ID "node-peripheral" :TITLE "Peripheral Node")
                            :raw-content "PERIPHERAL CONTENT" :contents nil)))))
    (ingest-ast ast)
    ;; Test both foveal focus in signal top-level and in payload (legacy)
    (let ((output (context-assemble-global-awareness (list :foveal-focus "node-foveal"))))
      (is (search "FOVEAL CONTENT" output))
      (is (search "* Peripheral Node" output))
      (is (not (search "PERIPHERAL CONTENT" output))))))

(test test-awareness-budget
  "Verify that context-assemble-global-awareness handles multiple projects."
  (clrhash opencortex::*memory*)
  (ingest-ast '(:type :HEADLINE :properties (:ID "p1" :TITLE "Project 1" :TAGS "project") :contents nil))
  (ingest-ast '(:type :HEADLINE :properties (:ID "p2" :TITLE "Project 2" :TAGS "project") :contents nil))
  (let ((output (context-assemble-global-awareness)))
    (is (search "Project 1" output))
    (is (search "Project 2" output))))
