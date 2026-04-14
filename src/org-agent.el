;;; opencortex.el --- Probabilistic-Deterministic Lisp Machine Kernel for Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Amr
;;
;; Author: Amr
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience, org
;; URL: https://github.com/amr/opencortex

;;; Commentary:

;; opencortex provides a Probabilistic-Deterministic Lisp Machine interface for Emacs.
;; It acts as the sensor/actuator array, communicating with a persistent
;; Common Lisp daemon over a high-speed communication protocol socket.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'org-id)
(require 'org-element)

(defgroup opencortex nil
  "Emacs interface for the opencortex Common Lisp daemon."
  :group 'org)

(defcustom opencortex-port 9105
  "The port the opencortex daemon is listening on."
  :type 'integer
  :group 'opencortex)

(defcustom opencortex-host "127.0.0.1"
  "The host the opencortex daemon is running on."
  :type 'string
  :group 'opencortex)

(defcustom opencortex-executable-path "opencortex-server"
  "Path to the compiled opencortex-server binary.
If nil, Emacs will not attempt to start the daemon automatically and 
will assume you have started it manually (e.g., via SBCL)."
  :type '(choice (string :tag "Path to executable")
                 (const :tag "Manual daemon management" nil))
  :group 'opencortex)

(defvar opencortex--network-process nil
  "The network process connected to the daemon.")

(defvar opencortex--daemon-process nil
  "The spawned daemon child process.")

(defun opencortex--start-daemon ()
  "Start the daemon binary if not already running."
  (when (and opencortex-executable-path
             (not (process-live-p opencortex--daemon-process)))
    (message "opencortex: Starting daemon (%s)..." opencortex-executable-path)
    (setq opencortex--daemon-process
          (make-process
           :name "opencortex-daemon"
           :buffer "*opencortex-daemon*"
           :command (list opencortex-executable-path (number-to-string opencortex-port))
           :connection-type 'pipe))
    ;; Give it a moment to bind to the port
    (sleep-for 1.0)))

(defun opencortex-connect ()
  "Connect to the opencortex daemon, starting it if necessary."
  (interactive)
  (when opencortex--network-process
    (delete-process opencortex--network-process))
  
  (opencortex--start-daemon)
  
  (condition-case err
      (progn
        (setq opencortex--network-process
              (make-network-process
               :name "opencortex"
               :buffer "*opencortex*"
               :family 'ipv4
               :host opencortex-host
               :service opencortex-port
               :filter #'opencortex--filter
               :sentinel #'opencortex--sentinel))
        (message "opencortex: Connected to daemon."))
    (error
     (message "opencortex: Failed to connect to daemon at %s:%s. Ensure it is running. Error: %s" 
              opencortex-host opencortex-port (error-message-string err)))))

(defun opencortex-disconnect ()
  "Disconnect from the opencortex daemon."
  (interactive)
  (when opencortex--network-process
    (delete-process opencortex--network-process)
    (setq opencortex--network-process nil)
    (message "opencortex: Disconnected from network."))
  (when opencortex--daemon-process
    (delete-process opencortex--daemon-process)
    (setq opencortex--daemon-process nil)
    (message "opencortex: Killed daemon process.")))

(defun opencortex--filter (proc string)
  "Handle incoming communication protocol messages from the daemon via PROC with STRING."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (goto-char (point-max))
        (insert string)
        (opencortex--process-buffer buf proc)))))

(defun opencortex--process-buffer (buffer &optional proc)
  "Process the communication protocol message BUFFER, optionally using PROC."
  (with-current-buffer buffer
    (goto-char (point-min))
    (while (>= (buffer-size) 6)
      (let* ((len-str (buffer-substring (point-min) (+ (point-min) 6)))
             (msg-len (string-to-number len-str 16)))
        (if (>= (buffer-size) (+ 6 msg-len))
            (let* ((msg-start (+ (point-min) 6))
                   (msg-end (+ msg-start msg-len))
                   (msg-str (buffer-substring msg-start msg-end))
                   (plist (car (read-from-string msg-str))))
              (delete-region (point-min) msg-end)
              (opencortex--handle-message proc plist))
          ;; Message incomplete, stop loop
          (goto-char (point-max))
          (setq msg-len 1000000)))))) ; Break loop

(defun opencortex--plist-get (plist prop)
  "Case-insensitive keyword lookup for communication protocol compatibility."
  (or (plist-get plist prop)
      (plist-get plist (intern (upcase (symbol-name prop))))
      (plist-get plist (intern (downcase (symbol-name prop))))))

(defun opencortex--handle-message (proc plist)
  "Route and execute incoming communication protocol messages from PROC using PLIST."
  (let ((type (opencortex--plist-get plist :type))
        (id (opencortex--plist-get plist :id))
        (payload (or (opencortex--plist-get plist :payload) plist)))
    (cond
     ((member type '(:request :REQUEST))
      (opencortex--execute-request proc id payload))
     ((member type '(:response :RESPONSE))
      (message "opencortex: Received response for ID %s" id))
     ((member type '(:log :LOG))
      (let ((text (opencortex--plist-get payload :text)))
        (opencortex--insert-to-history (concat "[reasoning] " text "\n") 'opencortex-system-face)))
     (t (message "opencortex: Received unknown message type %s" type)))))

(defun opencortex--execute-request (proc id payload)
  "Execute an actuator request from the daemon via PROC with ID and PAYLOAD."
  (let ((action (opencortex--plist-get payload :action)))
    (cond
     ((member action '(:eval :EVAL))
      (let ((code (opencortex--plist-get payload :code)))
        (condition-case err
            (let ((result (eval (read code))))
              (opencortex-send 
               `(:type :RESPONSE :id ,id :payload (:status :success :result ,(format "%s" result)))))
          (error
           (opencortex-send 
            `(:type :RESPONSE :id ,id :payload (:status :error :message ,(error-message-string err))))))))
     ((member action '(:message :MESSAGE))
      (message "opencortex [DAEMON]: %s" (opencortex--plist-get payload :text))
      (opencortex-send `(:type :RESPONSE :id ,id :payload (:status :success))))
     ((member action '(:insert-at-end :INSERT-AT-END))
      (let ((text (opencortex--plist-get payload :text)))
        (opencortex--insert-to-history (concat "\nAGENT: " text "\n\n"))
        (opencortex-send `(:type :RESPONSE :id ,id :payload (:status :success)))))
     ((member action '(:refactor-subtree :REFACTOR-SUBTREE))
      (let ((target-id (opencortex--plist-get payload :target-id))
            (properties (opencortex--plist-get payload :properties)))
        (condition-case err
            (save-excursion
              (when target-id (org-id-goto target-id))
              (dolist (prop properties)
                (org-set-property (car prop) (cdr prop)))
              (opencortex-send `(:type :RESPONSE :id ,id :payload (:status :success))))
          (error
           (opencortex-send 
            `(:type :RESPONSE :id ,id :payload (:status :error :message ,(error-message-string err))))))))
     (t
      (message "opencortex: Unknown action %s" action)
      (opencortex-send `(:type :RESPONSE :id ,id :payload (:status :unsupported)))))))

(defun opencortex--sentinel (proc event)
  "Handle network process PROC lifecycle EVENT."
  (when (string-match "finished" event)
    (setq opencortex--network-process nil)
    (message "opencortex: Connection lost.")))

(defun opencortex-send (plist)
  "Send a Lisp PLIST to the daemon using communication protocol framing."
  (let* ((msg (prin1-to-string plist))
         (len (length msg))
         (framed (format "%06x%s" len msg)))
    (if (and opencortex--network-process (process-live-p opencortex--network-process))
        (process-send-string opencortex--network-process framed)
      (message "opencortex (offline): %s" framed))))

(defun opencortex--buffer-to-sexp ()
  "Transform the current Org buffer into a pure Lisp AST (plist)."
  (opencortex--clean-element (org-element-parse-buffer)))

(defun opencortex--clean-element (element)
  "Recursively transform an Org ELEMENT into a pure Lisp plist."
  (cond
   ((listp element)
    (let* ((type (car element))
           (props (nth 1 element))
           (children (nthcdr 2 element))
           (cleaned-props nil))
      ;; Filter and transform properties
      (cl-loop for (key val) on props by 'cddr do
               (unless (member key '(:standard-properties :parent :buffer))
                 (let ((json-val (cond
                                  ((stringp val) val)
                                  ((numberp val) val)
                                  ((booleanp val) val)
                                  (t (format "%s" val)))))
                   (setq cleaned-props (plist-put cleaned-props key json-val)))))
      ;; Explicitly capture TODO state
      (let ((todo (org-element-property :todo-keyword element)))
        (when todo
          (setq cleaned-props (plist-put cleaned-props :TODO-STATE (format "%s" todo)))))
      (list :type type
            :properties cleaned-props
            :contents (mapcar #'opencortex--clean-element children))))
   ((stringp element) element)
   (t (format "%s" element))))

;;; Sensors

(defun opencortex-notify-save ()
  "Sensor: Notify daemon with full Semantic Perception (AST) when saved."
  (when (and opencortex--network-process (derived-mode-p 'org-mode))
    (opencortex-send 
     `(:type :EVENT 
       :payload (:sensor :buffer-update 
                 :file ,(buffer-file-name) 
                 :state :saved
                 :ast ,(opencortex--buffer-to-sexp))))))

(defun opencortex-notify-point ()
  "Sensor: Notify daemon of the element currently at point (Incremental Perception).
This is much faster than parsing the entire buffer and allows for real-time
responsiveness to the user's cursor position."
  (when (and opencortex--network-process (derived-mode-p 'org-mode))
    (let ((element (org-element-at-point)))
      (opencortex-send
       `(:type :EVENT
         :payload (:sensor :point-update
                   :file ,(buffer-file-name)
                   :element ,(opencortex--clean-element element)))))))

;;; Interaction Commands

(defun opencortex-set-model-cascade (cascade-string)
  "Set the ordered list of LLM providers to use as fallbacks.
CASCADE-STRING should be a comma-separated list of keywords, 
e.g., ':gemini,:openai,:ollama'."
  (interactive "sEnter model cascade (e.g. :gemini,:openai): ")
  (unless opencortex--network-process
    (opencortex-connect))
  (let ((cascade (mapcar #'intern (split-string cascade-string ","))))
    (opencortex-send 
     `(:type :REQUEST 
       :id ,(truncate (float-time))
       :target :system
       :payload (:action :set-cascade :cascade ,cascade)))
    (message "opencortex: Requesting model cascade update to %s" cascade)))
(defgroup opencortex-faces nil
  "Faces for the opencortex chat interface."
  :group 'opencortex)

(defface opencortex-user-face
  '((((class color) (background dark)) :foreground "LightSkyBlue" :weight bold)
    (((class color) (background light)) :foreground "blue" :weight bold)
    (t :weight bold :underline t))
  "Face for user messages in chat history."
  :group 'opencortex-faces)

(defface opencortex-system-face
  '((t :slant italic :foreground "gray50"))
  "Face for system and reasoning logs."
  :group 'opencortex-faces)

(defun opencortex-chat ()
  "Modern chat interface for the opencortex kernel.
Opens a history buffer and a dedicated input area."
  (interactive)
  (let ((chat-buf (get-buffer-create "*opencortex-chat*"))
        (input-buf (get-buffer-create "*opencortex-input*")))
    ;; History Buffer Setup
    (with-current-buffer chat-buf
      (unless (eq major-mode 'special-mode)
        (special-mode)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "--- opencortex History ---\n\n"))))
    
    ;; Input Buffer Setup
    (with-current-buffer input-buf
      (unless (eq major-mode 'org-mode)
        (org-mode)
        (local-set-key (kbd "C-c C-c") #'opencortex-chat-send)
        (local-set-key (kbd "C-c C-k") #'opencortex-interrupt))
      (let ((inhibit-read-only t))
        (delete-region (point-min) (point-max))
        (insert "# Type your message and press C-c C-c to send.\n")))

    ;; Layout: Chat History (Top), Input Area (Bottom)
    (delete-other-windows)
    (switch-to-buffer chat-buf)
    (let ((win (split-window-below -6))) ; 6 lines for input
      (set-window-buffer win input-buf)
      (select-window win))))
(defun opencortex-interrupt ()
  "Interrupt the opencortex reasoning loop."
  (interactive)
  (unless opencortex--network-process
    (opencortex-connect))
  (opencortex-send 
   `(:type :EVENT 
     :payload (:sensor :interrupt)))
  (message "opencortex: Interrupt signal sent."))

(defun opencortex--insert-to-history (text &optional face)
  "Insert TEXT into the chat history buffer with optional FACE and scroll."
  (let ((buf (get-buffer-create "*opencortex-chat*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (point-max))
          (insert (if face (propertize text 'face face) text)))
        ;; Force scroll in all windows showing this buffer
        (walk-windows
         (lambda (w)
           (when (eq (window-buffer w) buf)
             (set-window-point w (point-max))))
         nil t)))))

(defun opencortex-chat-send ()
  "Send the current chat buffer content to the agent."
  (interactive)
  (unless opencortex--network-process
    (opencortex-connect))
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (clean-text (string-trim (replace-regexp-in-string "^#.*\n" "" text))))
    (when (> (length clean-text) 0)
      ;; Append to history with styling
      (opencortex--insert-to-history (concat "YOU: " clean-text "\n\n") 'opencortex-user-face)
      
      ;; Clear input buffer
      (let ((inhibit-read-only t))
        (delete-region (point-min) (point-max))
        (insert "# Type your message and press C-c C-c to send.\n"))
      
      ;; Send to daemon
      (opencortex-send 
       `(:type :EVENT 
         :payload (:sensor :chat-message 
                   :text ,clean-text)))
      (message "opencortex: Message sent."))))

(defun opencortex-auth-google (code)
  "Submit the Google OAuth authorization CODE to the daemon."
  (interactive "sEnter Google Authorization Code: ")
  (unless opencortex--network-process
    (opencortex-connect))
  (opencortex-send 
   `(:type :REQUEST 
     :id ,(truncate (float-time))
     :target :system
     :payload (:action :auth-google-code :code ,code)))
  (message "opencortex: Authorization code sent to daemon."))

(defun opencortex-organize-subtree ()
...
  "Command: Ask the agent to organize the current Org subtree."
  (interactive)
  (opencortex-run-command :organize-subtree))

(defun opencortex-summarize-buffer ()
  "Command: Ask the agent to summarize the current buffer."
  (interactive)
  (opencortex-run-command :summarize-buffer))

(defun opencortex-run-command (command-type)
  "Generic runner for high-level COMMAND-TYPE."
  (unless opencortex--network-process
    (opencortex-connect))
  (let ((ast (opencortex--buffer-to-sexp)))
    (opencortex-send 
     `(:type :EVENT 
       :payload (:sensor :user-command 
                 :command ,command-type
                 :file ,(buffer-file-name)
                 :ast ,ast)))
    (message "opencortex: Requesting '%s'..." command-type)))

;;;###autoload
(define-minor-mode opencortex-mode
  "Global minor mode for the opencortex Probabilistic-Deterministic kernel.
When enabled, this mode starts the Lisp daemon (if configured)
and establishes the network connection to enable proactive
Org-mode sensing."
  :global t
  :group 'opencortex
  (if opencortex-mode
      (progn
        (add-hook 'after-save-hook #'opencortex-notify-save)
        (add-hook 'post-command-hook #'opencortex-notify-point)
        (add-hook 'kill-emacs-hook #'opencortex-disconnect)
        (opencortex-connect))
    (remove-hook 'after-save-hook #'opencortex-notify-save)
    (remove-hook 'post-command-hook #'opencortex-notify-point)
    (remove-hook 'kill-emacs-hook #'opencortex-disconnect)
    (opencortex-disconnect)))

(provide 'opencortex)
;;; opencortex.el ends here
