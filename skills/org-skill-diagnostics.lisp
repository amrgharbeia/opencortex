(in-package :opencortex)

(defvar *doctor-required-binaries* '("sbcl" "emacs" "git" "socat" "nc")
  "List of external binaries required for full system operation.")

(defvar *doctor-package-map*
  '(("sbcl" . "sbcl")
    ("emacs" . "emacs")
    ("git" . "git")
    ("socat" . "socat")
    ("nc" . "netcat-openbsd")
    ("curl" . "curl")
    ("rlwrap" . "rlwrap"))
  "Map binary names to apt package names.")

(defvar *doctor-missing-deps* nil
  "List of missing dependencies populated by doctor-check-dependencies.")

(defvar *doctor-auto-install* t
  "When T, doctor will attempt to install missing dependencies automatically.")

(defun doctor-check-dependencies ()
  "Verifies that required external binaries are available in the PATH via shell probe."
  (setf *doctor-missing-deps* nil)
  (let ((all-ok t))
    (format t "DOCTOR: Checking system dependencies...~%")
    (dolist (dep *doctor-required-binaries*)
      (let ((path (ignore-errors
                    (uiop:run-program (list "which" dep)
                                      :output :string :ignore-error-status t))))
        (if (and path (> (length path) 0))
            (format t "  [OK] Found ~a~%" dep)
            (progn
              (format t "  [FAIL] Missing binary: ~a~%" dep)
              (push dep *doctor-missing-deps*)
              (setf all-ok nil)))))
    (when (and all-ok (null *doctor-missing-deps*))
      (format t "DOCTOR: All dependencies satisfied.~%"))
    all-ok))

(defun doctor-install-dependencies ()
  "Attempts to install missing system dependencies via apt."
  (when (null *doctor-missing-deps*)
    (format t "DOCTOR: No missing dependencies to install.~%")
    (return-from doctor-install-dependencies t))

  (format t "DOCTOR: Attempting to install ~a missing dependencies...~%" (length *doctor-missing-deps*))

  (let ((packages (remove-duplicates
                   (mapcar (lambda (dep)
                             (or (cdr (assoc dep *doctor-package-map* :test #'string=))
                                 dep))
                           *doctor-missing-deps*)
                   :test #'string=)))
    (format t "DOCTOR: Packages to install: ~a~%" packages)

    (let ((cmd (format nil "apt-get install -y ~{~a~^ ~}" packages)))
      (format t "DOCTOR: Running: ~a~%" cmd)
      (handler-case
          (let ((output (uiop:run-program cmd
                                           :output :string
                                           :error-output :string
                                           :external-format :utf-8)))
            (if (zerop (uiop:run-program (format nil "which ~a" (car *doctor-missing-deps*))
                                          :ignore-error-status t))
                (progn
                  (format t "DOCTOR: Dependencies installed successfully.~%")
                  (setf *doctor-missing-deps* nil)
                  t)
                (progn
                  (format t "DOCTOR: Installation failed. Output: ~a~%" output)
                  nil)))
        (error (c)
          (format t "DOCTOR: Installation error: ~a~%" c)
          nil)))))

(defun doctor-check-env ()
  "Validates XDG directories and environment configuration."
  (format t "DOCTOR: Checking XDG environment...~%")
  (let ((all-ok t)
        (config-dir (uiop:getenv "OC_CONFIG_DIR"))
        (data-dir (uiop:getenv "OC_DATA_DIR"))
        (state-dir (uiop:getenv "OC_STATE_DIR"))
        (memex-dir (uiop:getenv "MEMEX_DIR")))

    (flet ((check-dir (name path critical)
             (if (and path (> (length path) 0))
                 (if (uiop:directory-exists-p path)
                     (format t "  [OK] ~a: ~a~%" name path)
                     (progn
                       (format t "  [FAIL] ~a directory missing: ~a~%" name path)
                       (when critical (setf all-ok nil))))
                 (progn
                   (format t "  [FAIL] ~a variable not set.~%" name)
                   (when critical (setf all-ok nil))))))

      (check-dir "Config (OC_CONFIG_DIR)" config-dir t)
      (check-dir "Data (OC_DATA_DIR)" data-dir t)
      (check-dir "State (OC_STATE_DIR)" state-dir t)
      (check-dir "Memex (MEMEX_DIR)" memex-dir t))
    all-ok))

(defun doctor-check-llm ()
  "Tests connectivity to LLM providers. Returns T if at least one provider is configured."
  (format t "DOCTOR: Checking LLM connectivity...~%")
  (let ((providers '((:openrouter . "OPENROUTER_API_KEY")
                    (:anthropic . "ANTHROPIC_API_KEY")
                    (:openai . "OPENAI_API_KEY")
                    (:groq . "GROQ_API_KEY")
                    (:gemini . "GEMINI_API_KEY")
                    (:ollama . "OLLAMA_URL")))
        (configured nil))
    (dolist (p providers)
      (let ((env-val (uiop:getenv (cdr p))))
        (cond
          ((and env-val (> (length env-val) 0))
           (format t "  [OK] ~a configured~%" (car p))
           (setf configured t))
          ((eq (car p) :ollama)
           (let ((ollama-check (ignore-errors
                                 (uiop:run-program '("curl" "-s" "http://localhost:11434/api/tags")
                                                    :output :string :ignore-error-status t))))
             (when (and ollama-check (search "\"models\"" ollama-check))
               (format t "  [OK] Ollama local model server detected~%")
               (setf configured t)))))))
    (if configured
        (progn
          (format t "  [OK] LLM provider(s) available~%")
          t)
        (progn
          (format t "  [WARN] No LLM provider configured.~%")
          (format t "  Run 'opencortex setup' to configure a provider.~%")
          t))))

(defun doctor-run-all (&key (auto-install t))
  "Executes the full diagnostic suite and returns T if system is healthy."
  (format t "==================================================~%")
  (format t " OPENCORTEX DOCTOR: Commencing Health Check~%")
  (format t "==================================================~%")
  (let ((dep-ok (doctor-check-dependencies)))
    (when (and (not dep-ok) auto-install *doctor-auto-install*)
      (format t "DOCTOR: Attempting automatic installation...~%")
      (setf dep-ok (doctor-install-dependencies))
      (when dep-ok
        (setf dep-ok (doctor-check-dependencies))))
    (let ((env-ok (doctor-check-env))
          (llm-ok (doctor-check-llm)))
      (format t "==================================================~%")
      (if (and dep-ok env-ok)
          (progn
            (format t " ✓ SYSTEM HEALTHY: Ready for ignition.~%")
            t)  ;; Explicitly return T
          (progn
            (format t "==================================================~%")
            (format t " ISSUES FOUND:~%")
            (when (not dep-ok)
              (format t "  - Missing system dependencies~%"))
            (when (not llm-ok)
              (format t "  - No LLM provider configured~%"))
            (format t "~%")
            (format t " RECOMMENDED ACTIONS:~%")
            (format t "  1. Run 'opencortex setup' to configure everything~%")
            (format t "  2. Or run 'opencortex doctor --fix' for auto-repair~%")
            (format t "==================================================~%")
            nil)))))  ;; Return nil when issues found

(defun doctor-main ()
  "Entry point for the 'doctor' CLI command."
  (if (doctor-run-all)
      (uiop:quit 0)
      (uiop:quit 1)))

(defskill :skill-diagnostics
  :priority 100
  :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :heartbeat))
  :deterministic (lambda (action ctx) (declare (ignore action ctx)) nil))
