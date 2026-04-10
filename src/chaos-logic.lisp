(defun chaos-inject-error (sensor-type)
  "Injects a synthetic error into a specific sensor pipeline."
  (org-agent:kernel-log "CHAOS - Injecting synthetic error into ~a sensor..." sensor-type)
  (org-agent:inject-stimulus 
   `(:type :EVENT :payload (:sensor ,sensor-type :error "SYNTHETIC_CHAOS_ERROR"))))

(defun chaos-stress-test (action context)
  "Executes a randomized stress test by injecting failures into the system."
  (declare (ignore context))
  (let* ((payload (getf action :payload))
         (mode (or (getf payload :mode) :random))
         (intensity (or (getf payload :intensity) 3)))
    (org-agent:kernel-log "CHAOS - Commencing stress test (Mode: ~a, Intensity: ~a)" mode intensity)
    (case mode
      (:random (dotimes (i intensity)
                 (let ((failure-type (nth (random 3) '(:test-failure :shell-timeout :llm-error))))
                   (org-agent:inject-stimulus 
                    `(:type :EVENT :payload (:sensor :chaos-injection :type ,failure-type))))))
      (:shell (org-agent:inject-stimulus 
               `(:type :EVENT :payload (:sensor :shell-response :cmd "git push" :exit-code 128 :stderr "fatal: network unreachable")))))
    (format nil "SUCCESS - Chaos stress test initiated.")))
