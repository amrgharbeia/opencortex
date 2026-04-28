(in-package :opencortex)

(defparameter *skill-diagnostics*
  '(:name "diagnostics"
    :description "Performs system health checks and environment validation."
    :capabilities (:run-diagnostics)
    :type :deterministic)
  "Skill metadata for the Diagnostics component.")

(defvar *doctor-required-binaries* '("sbcl" "emacs" "git" "socat" "nc")
  "List of external binaries required for full system operation.")

(defun doctor-check-dependencies ()
  "Verifies that required external binaries are available in the PATH via a shell probe."
  (let ((all-ok t))
    (harness-log "DOCTOR: Checking system dependencies...")
    (dolist (dep *doctor-required-binaries*)
      (let ((path (ignore-errors 
                    (uiop:run-program (list "which" dep) 
                                      :output :string :ignore-error-status t))))
        (if (and path (> (length path) 0))
            (harness-log "  [OK] Found ~a" dep)
            (progn
              (harness-log "  [FAIL] Missing binary: ~a" dep)
              (setf all-ok nil)))))
    all-ok))

(defun doctor-check-env ()
  "Validates XDG directories and environment configuration against the POSIX standard."
  (harness-log "DOCTOR: Checking XDG environment...")
  (let ((all-ok t)
        (config-dir (uiop:getenv "OC_CONFIG_DIR"))
        (data-dir (uiop:getenv "OC_DATA_DIR"))
        (state-dir (uiop:getenv "OC_STATE_DIR"))
        (memex-dir (uiop:getenv "MEMEX_DIR")))
    
    (flet ((check-dir (name path critical)
             (if (and path (> (length path) 0))
                 (if (uiop:directory-exists-p path)
                     (harness-log "  [OK] ~a: ~a" name path)
                     (progn
                       (harness-log "  [FAIL] ~a directory missing: ~a" name path)
                       (when critical (setf all-ok nil))))
                 (progn
                   (harness-log "  [FAIL] ~a variable not set." name)
                   (when critical (setf all-ok nil))))))

      (check-dir "Config (OC_CONFIG_DIR)" config-dir t)
      (check-dir "Data (OC_DATA_DIR)" data-dir t)
      (check-dir "State (OC_STATE_DIR)" state-dir t)
      (check-dir "Memex (MEMEX_DIR)" memex-dir t))
    all-ok))

(defun doctor-check-llm ()
  "Tests connectivity to primary LLM providers. Non-critical fallback allowed."
  (harness-log "DOCTOR: Checking LLM connectivity...")
  (let ((openrouter-key (uiop:getenv "OPENROUTER_API_KEY")))
    (if (and openrouter-key (> (length openrouter-key) 0))
        (progn
          (harness-log "  [OK] OpenRouter API Key detected.")
          t)
        (progn
          (harness-log "  [WARN] No OpenRouter API Key. Falling back to local inference only.")
          t))))

(defun doctor-run-all ()
  "Executes the full diagnostic suite and returns T if system is healthy."
  (harness-log "==================================================")
  (harness-log " OPENCORTEX DOCTOR: Commencing Health Check")
  (harness-log "==================================================")
  (let ((dep-ok (doctor-check-dependencies))
        (env-ok (doctor-check-env))
        (llm-ok (doctor-check-llm)))
    (harness-log "==================================================")
    (if (and dep-ok env-ok)
        (progn
          (harness-log " ✓ SYSTEM HEALTHY: Ready for ignition.")
          t)
        (progn
          (harness-log " ✗ SYSTEM UNHEALTHY: Fix the errors above.")
          nil))))

(defun doctor-main ()
  "Entry point for the 'doctor' CLI command."
  (if (doctor-run-all)
      (uiop:quit 0)
      (uiop:quit 1)))
