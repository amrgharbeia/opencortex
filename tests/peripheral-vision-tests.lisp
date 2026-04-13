(defpackage :org-agent-peripheral-vision-tests
  (:use :cl :fiveam :org-agent)
  (:export #:vision-suite))
(in-package :org-agent-peripheral-vision-tests)

(def-suite vision-suite
  :description "Verification of Foveal-Peripheral context model.")
(in-suite vision-suite)

(test test-foveal-rendering
  "Verify that the foveal target is rendered with content, while siblings are skeletal."
  (clrhash org-agent::*memory*)
  (let* ((ast '(:type :HEADLINE :properties (:ID "proj-root" :TITLE "Project" :TAGS "project")
                :contents ((:type :HEADLINE :properties (:ID "node-foveal" :TITLE "Foveal Node")
                            :raw-content "FOVEAL CONTENT" :contents nil)
                           (:type :HEADLINE :properties (:ID "node-peripheral" :TITLE "Peripheral Node")
                            :raw-content "PERIPHERAL CONTENT" :contents nil)))))
    (ingest-ast ast)
    (let ((output (context-assemble-global-awareness (list :payload (list :target-id "node-foveal")))))
      ;; Foveal node should have its content
      (is (search "FOVEAL CONTENT" output))
      ;; Peripheral node should be skeletal (only title/ID)
      (is (search "* Peripheral Node" output))
      (is (not (search "PERIPHERAL CONTENT" output))))))

(test test-awareness-budget
  "Verify that context-assemble-global-awareness handles multiple projects."
  (clrhash org-agent::*memory*)
  (ingest-ast '(:type :HEADLINE :properties (:ID "p1" :TITLE "Project 1" :TAGS "project") :contents nil))
  (ingest-ast '(:type :HEADLINE :properties (:ID "p2" :TITLE "Project 2" :TAGS "project") :contents nil))
  (let ((output (context-assemble-global-awareness)))
    (is (search "Project 1" output))
    (is (search "Project 2" output))))
