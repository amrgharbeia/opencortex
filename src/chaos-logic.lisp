(in-package :org-agent)

(defun chaos-inject-error (sensor-type)
  "Injects a synthetic error into a specific sensor pipeline."
  (unless *chaos-enabled-p*
    (harness-log "CHAOS ERROR - Injection blocked. Production gate is ACTIVE.")
    (return-from chaos-inject-error nil))
  (harness-log "CHAOS - Injecting synthetic error into ~a sensor..." sensor-type)
  (inject-stimulus 
   `(:type :EVENT :payload (:sensor ,sensor-type :error "SYNTHETIC_CHAOS_ERROR"))))

(defun chaos-stress-test (action context)
  "Executes a randomized stress test by injecting failures into the system."
  (declare (ignore context))
  (unless *chaos-enabled-p*
    (harness-log "CHAOS ERROR - Stress test blocked. Production gate is ACTIVE.")
    (return-from chaos-stress-test "FAILURE - Production gate active."))
  (let* ((payload (getf action :payload))
         (mode (or (getf payload :mode) :random))
         (intensity (or (getf payload :intensity) 3)))
    (harness-log "CHAOS - Commencing stress test (Mode: ~a, Intensity: ~a)" mode intensity)
    (snapshot-memory)
    (case mode
      (:random (dotimes (i intensity)
                 (let ((failure-type (nth (random 3) '(:test-failure :shell-timeout :llm-error))))
                   (inject-stimulus 
                    `(:type :EVENT :payload (:sensor :chaos-injection :type ,failure-type))))))
      (:shell (inject-stimulus 
               `(:type :EVENT :payload (:sensor :shell-response :cmd "git push" :exit-code 128 :stderr "fatal: network unreachable")))))
    (snapshot-memory)
    (format nil "SUCCESS - Chaos stress test initiated.")))

(defun chaos-enable ()
  "Disables the production gate and allows chaos injection."
  (setf *chaos-enabled-p* t)
  (harness-log "CHAOS - Production gate DISABLED. Chaos injection is now ALLOWED.")
  t)

(defun chaos-disable ()
  "Enables the production gate and blocks chaos injection."
  (setf *chaos-enabled-p* nil)
  (harness-log "CHAOS - Production gate ENABLED. Chaos injection is now BLOCKED.")
  t)
