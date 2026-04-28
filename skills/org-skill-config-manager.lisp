(in-package :opencortex)

(defparameter *skill-config-manager*
  '(:name "config-manager"
    :description "Manages system settings and LLM provider configurations."
    :capabilities (:configure-provider :run-setup-wizard)
    :type :deterministic)
  "Skill metadata for the Config Manager.")

(defvar *provider-templates*
  '((:ollama . (:name "Ollama (Local)" :fields ((:url :label "URL") (:model :label "Model")) :default-url "http://localhost:11434" :default-model "llama3"))
    (:openrouter . (:name "OpenRouter" :fields ((:key :label "API Key" :secret t) (:model :label "Model")) :default-model "anthropic/claude-3-opus-20240229"))
    (:openai . (:name "OpenAI" :fields ((:key :label "API Key" :secret t) (:model :label "Model")) :default-model "gpt-4-turbo"))
    (:groq . (:name "Groq" :fields ((:key :label "API Key" :secret t) (:model :label "Model")) :default-model "mixtral-8x7b-32768"))
    (:gemini . (:name "Google Gemini" :fields ((:key :label "API Key" :secret t) (:model :label "Model")) :default-model "gemini-1.5-pro"))
    (:anthropic . (:name "Anthropic" :fields ((:key :label "API Key" :secret t) (:model :label "Model")) :default-model "claude-3-5-sonnet-20240620")))
  "Templates for supported LLM providers.")

(defvar *providers* nil "Global registry of configured LLM providers.")

(defun get-oc-config-dir ()
  "Returns the XDG-compliant config directory for OpenCortex."
  (let ((env (uiop:getenv "OC_CONFIG_DIR")))
    (if (and env (> (length env) 0))
        (uiop:ensure-directory-pathname env)
        (uiop:merge-pathnames* ".config/opencortex/" (user-homedir-pathname)))))

(defun save-providers ()
  "Persist provider configuration to XDG config directory."
  (let ((path (merge-pathnames "providers.lisp" (get-oc-config-dir))))
    (ensure-directories-exist path)
    (with-open-file (s path :direction :output :if-exists :supersede)
      (format s ";;; OpenCortex Provider Metadata~%~s~%" *providers*))))

(defun prompt-for (label &optional default)
  "Prompts the user for input on the CLI."
  (format t "~a~@[ [~a]~]: " label default)
  (finish-output)
  (let ((input (read-line)))
    (if (string= input "")
        (or default "")
        input)))

(defun save-secret (provider field val)
  "Appends a secret to the XDG .env file."
  (let ((env-file (merge-pathnames ".env" (get-oc-config-dir)))
        (var-name (format nil "~:@(~a_~a~)" provider field)))
    (ensure-directories-exist env-file)
    (with-open-file (out env-file :direction :output :if-exists :append :if-does-not-exist :create)
      (format out "~a=~a~%" var-name val))
    (setf (uiop:getenv var-name) val)))

(defun register-provider (id config)
  "Update the global provider registry."
  (setf (getf *providers* id) config))

(defun configure-provider (id)
  "Guided configuration for a specific LLM provider template."
  (let* ((template (cdr (assoc id *provider-templates*)))
         (fields (getf template :fields))
         (config nil))
    (format t "~%--- Configuring ~a ---~%" (getf template :name))
    (dolist (field-spec fields)
      (let* ((field (first field-spec))
             (label (getf (rest field-spec) :label))
             (is-secret (getf (rest field-spec) :secret))
             (default-key (intern (format nil "DEFAULT-~a" field) :keyword))
             (default (getf template default-key))
             (val (prompt-for label default)))
        (if is-secret
            (save-secret id field val)
            (setf (getf config field) val))))
    (register-provider id config)
    (format t "✓ ~a metadata registered.~%" (getf template :name))))

(defun run-setup-wizard ()
  "Entry point for the interactive OpenCortex Lisp Setup Wizard."
  (format t "=== OpenCortex: Advanced Setup Wizard ===~%")
  (let ((user (prompt-for "Your Name" "User"))
        (agent (prompt-for "Agent Name" "OpenCortex")))
    (format t "Welcome, ~a. I am ~a.~%" user agent))
  (format t "~%Available Providers:~%")
  (loop for (id . data) in *provider-templates* do (format t "  ~a: ~a~%" id (getf data :name)))
  (format t "~%Enter provider IDs to configure (comma separated, or 'all'): ")
  (finish-output)
  (let* ((input (read-line))
         (ids (if (string= input "all")
                  (mapcar #'car *provider-templates*)
                  (mapcar (lambda (s) (intern (string-upcase (string-trim " " s)) :keyword))
                          (uiop:split-string input :separator ",")))))
    (dolist (id ids)
      (when (assoc id *provider-templates*)
        (configure-provider id))))
  (save-providers)
  (format t "~%Setup complete. Running diagnostics...~%")
  (doctor-run-all))
