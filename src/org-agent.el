;;; org-agent.el --- Neurosymbolic Lisp Machine Kernel for Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Amr
;;
;; Author: Amr
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience, org
;; URL: https://github.com/amr/org-agent

;;; Commentary:

;; org-agent provides a Neurosymbolic Lisp Machine interface for Emacs.
;; It acts as the sensor/actuator array, communicating with a persistent
;; Common Lisp daemon over a high-speed OACP socket.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'org-id)
(require 'org-element)

(defgroup org-agent nil
  "Emacs interface for the org-agent Common Lisp daemon."
  :group 'org)

(defcustom org-agent-port 9105
  "The port the org-agent daemon is listening on."
  :type 'integer
  :group 'org-agent)

(defcustom org-agent-host "127.0.0.1"
  "The host the org-agent daemon is running on."
  :type 'string
  :group 'org-agent)

(defcustom org-agent-executable-path "org-agent-server"
  "Path to the compiled org-agent-server binary.
If nil, Emacs will not attempt to start the daemon automatically and 
will assume you have started it manually (e.g., via SBCL)."
  :type '(choice (string :tag "Path to executable")
                 (const :tag "Manual daemon management" nil))
  :group 'org-agent)

(defvar org-agent--network-process nil
  "The network process connected to the daemon.")

(defvar org-agent--daemon-process nil
  "The spawned daemon child process.")

(defun org-agent--start-daemon ()
  "Start the daemon binary if not already running."
  (when (and org-agent-executable-path
             (not (process-live-p org-agent--daemon-process)))
    (message "org-agent: Starting daemon (%s)..." org-agent-executable-path)
    (setq org-agent--daemon-process
          (make-process
           :name "org-agent-daemon"
           :buffer "*org-agent-daemon*"
           :command (list org-agent-executable-path (number-to-string org-agent-port))
           :connection-type 'pipe))
    ;; Give it a moment to bind to the port
    (sleep-for 1.0)))

(defun org-agent-connect ()
  "Connect to the org-agent daemon, starting it if necessary."
  (interactive)
  (when org-agent--network-process
    (delete-process org-agent--network-process))
  
  (org-agent--start-daemon)
  
  (condition-case err
      (progn
        (setq org-agent--network-process
              (make-network-process
               :name "org-agent"
               :buffer "*org-agent*"
               :family 'ipv4
               :host org-agent-host
               :service org-agent-port
               :filter #'org-agent--filter
               :sentinel #'org-agent--sentinel))
        (message "org-agent: Connected to daemon."))
    (error
     (message "org-agent: Failed to connect to daemon at %s:%s. Ensure it is running. Error: %s" 
              org-agent-host org-agent-port (error-message-string err)))))

(defun org-agent-disconnect ()
  "Disconnect from the org-agent daemon."
  (interactive)
  (when org-agent--network-process
    (delete-process org-agent--network-process)
    (setq org-agent--network-process nil)
    (message "org-agent: Disconnected from network."))
  (when org-agent--daemon-process
    (delete-process org-agent--daemon-process)
    (setq org-agent--daemon-process nil)
    (message "org-agent: Killed daemon process.")))

(defun org-agent--filter (proc string)
  "Handle incoming OACP messages from the daemon via PROC with STRING."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (goto-char (point-max))
        (insert string)
        (org-agent--process-buffer buf proc)))))

(defun org-agent--process-buffer (buffer &optional proc)
  "Process the OACP message BUFFER, optionally using PROC."
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
              (org-agent--handle-message proc plist))
          ;; Message incomplete, stop loop
          (goto-char (point-max))
          (setq msg-len 1000000)))))) ; Break loop

(defun org-agent--plist-get (plist prop)
  "Case-insensitive keyword lookup for OACP compatibility."
  (or (plist-get plist prop)
      (plist-get plist (intern (upcase (symbol-name prop))))
      (plist-get plist (intern (downcase (symbol-name prop))))))

(defun org-agent--handle-message (proc plist)
  "Route and execute incoming OACP messages from PROC using PLIST."
  (let ((type (org-agent--plist-get plist :type))
        (id (org-agent--plist-get plist :id))
        (payload (org-agent--plist-get plist :payload)))
    (cond
     ((member type '(:request :REQUEST))
      (org-agent--execute-request proc id payload))
     ((member type '(:response :RESPONSE))
      (message "org-agent: Received response for ID %s" id))
     (t (message "org-agent: Received unknown message type %s" type)))))

(defun org-agent--execute-request (proc id payload)
  "Execute an actuator request from the daemon via PROC with ID and PAYLOAD."
  (let ((action (org-agent--plist-get payload :action)))
    (cond
     ((member action '(:eval :EVAL))
      (let ((code (org-agent--plist-get payload :code)))
        (condition-case err
            (let ((result (eval (read code))))
              (org-agent-send 
               `(:type :RESPONSE :id ,id :payload (:status :success :result ,(format "%s" result)))))
          (error
           (org-agent-send 
            `(:type :RESPONSE :id ,id :payload (:status :error :message ,(error-message-string err))))))))
     ((member action '(:message :MESSAGE))
      (message "org-agent [DAEMON]: %s" (org-agent--plist-get payload :text))
      (org-agent-send `(:type :RESPONSE :id ,id :payload (:status :success))))
     ((member action '(:insert-at-end :INSERT-AT-END))
      (let ((buf-name (org-agent--plist-get payload :buffer))
            (text (org-agent--plist-get payload :text)))
        (save-excursion
          (with-current-buffer (get-buffer-create buf-name)
            (goto-char (point-max))
            ;; If there is a "Thinking..." status from the client, remove it.
            (when (search-backward "** Thinking..." nil t)
              (delete-region (point) (point-max))
              ;; Remove the preceding newline if it exists
              (when (eq (char-before) ?\n)
                (backward-delete-char 1)))
            (goto-char (point-max))
            (insert "\n" text "\n")
            (org-agent-send `(:type :RESPONSE :id ,id :payload (:status :success)))))))
     ((member action '(:refactor-subtree :REFACTOR-SUBTREE))
      (let ((target-id (org-agent--plist-get payload :target-id))
            (properties (org-agent--plist-get payload :properties)))
        (condition-case err
            (save-excursion
              (when target-id (org-id-goto target-id))
              (dolist (prop properties)
                (org-set-property (car prop) (cdr prop)))
              (org-agent-send `(:type :RESPONSE :id ,id :payload (:status :success))))
          (error
           (org-agent-send 
            `(:type :RESPONSE :id ,id :payload (:status :error :message ,(error-message-string err))))))))
     (t
      (message "org-agent: Unknown action %s" action)
      (org-agent-send `(:type :RESPONSE :id ,id :payload (:status :unsupported)))))))

(defun org-agent--sentinel (proc event)
  "Handle network process PROC lifecycle EVENT."
  (when (string-match "finished" event)
    (setq org-agent--network-process nil)
    (message "org-agent: Connection lost.")))

(defun org-agent-send (plist)
  "Send a Lisp PLIST to the daemon using OACP framing."
  (let* ((msg (prin1-to-string plist))
         (len (length msg))
         (framed (format "%06x%s" len msg)))
    (if (and org-agent--network-process (process-live-p org-agent--network-process))
        (process-send-string org-agent--network-process framed)
      (message "org-agent (offline): %s" framed))))

(defun org-agent--buffer-to-sexp ()
  "Transform the current Org buffer into a pure Lisp AST (plist)."
  (org-agent--clean-element (org-element-parse-buffer)))

(defun org-agent--clean-element (element)
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
            :contents (mapcar #'org-agent--clean-element children))))
   ((stringp element) element)
   (t (format "%s" element))))

;;; Sensors

(defun org-agent-notify-save ()
  "Sensor: Notify daemon with full Semantic Perception (AST) when saved."
  (when (and org-agent--network-process (derived-mode-p 'org-mode))
    (org-agent-send 
     `(:type :EVENT 
       :payload (:sensor :buffer-update 
                 :file ,(buffer-file-name) 
                 :state :saved
                 :ast ,(org-agent--buffer-to-sexp))))))

(defun org-agent-notify-point ()
  "Sensor: Notify daemon of the element currently at point (Incremental Perception).
This is much faster than parsing the entire buffer and allows for real-time
responsiveness to the user's cursor position."
  (when (and org-agent--network-process (derived-mode-p 'org-mode))
    (let ((element (org-element-at-point)))
      (org-agent-send
       `(:type :EVENT
         :payload (:sensor :point-update
                   :file ,(buffer-file-name)
                   :element ,(org-agent--clean-element element)))))))

;;; Interaction Commands

(defun org-agent-set-model-cascade (cascade-string)
  "Set the ordered list of LLM providers to use as fallbacks.
CASCADE-STRING should be a comma-separated list of keywords, 
e.g., ':gemini,:openai,:ollama'."
  (interactive "sEnter model cascade (e.g. :gemini,:openai): ")
  (unless org-agent--network-process
    (org-agent-connect))
  (let ((cascade (mapcar #'intern (split-string cascade-string ","))))
    (org-agent-send 
     `(:type :REQUEST 
       :id ,(truncate (float-time))
       :target :system
       :payload (:action :set-cascade :cascade ,cascade)))
    (message "org-agent: Requesting model cascade update to %s" cascade)))

(defun org-agent-chat ()
  "Switch to the org-agent chat buffer, creating it if necessary."
  (interactive)
  (let ((buf (get-buffer-create "*org-agent-chat*")))
    (with-current-buffer buf
      (unless (eq major-mode 'org-mode)
        (org-mode)
        (local-set-key (kbd "C-c C-c") #'org-agent-chat-send)
        (insert "#+TITLE: org-agent Chat\n#+STARTUP: showall\n\n* Welcome to the Neurosymbolic Lisp Machine\n\nType your message below and press `C-c C-c` to send.\n\n")))
    (switch-to-buffer buf)
    (goto-char (point-max))))
(defun org-agent-chat-send ()
  "Send the current chat buffer content to the agent."
  (interactive)
  (unless org-agent--network-process
    (org-agent-connect))
  (let* ((text (buffer-substring-no-properties (point-min) (point-max))))
    (org-agent-send 
     `(:type :EVENT 
       :payload (:sensor :chat-message 
                 :text ,text)))
    (save-excursion
      (goto-char (point-max))
      (insert "\n\n** Thinking...\n"))
    (message "org-agent: Message sent.")))

(defun org-agent-auth-google (code)
  "Submit the Google OAuth authorization CODE to the daemon."
  (interactive "sEnter Google Authorization Code: ")
  (unless org-agent--network-process
    (org-agent-connect))
  (org-agent-send 
   `(:type :REQUEST 
     :id ,(truncate (float-time))
     :target :system
     :payload (:action :auth-google-code :code ,code)))
  (message "org-agent: Authorization code sent to daemon."))

(defun org-agent-organize-subtree ()
...
  "Command: Ask the agent to organize the current Org subtree."
  (interactive)
  (org-agent-run-command :organize-subtree))

(defun org-agent-summarize-buffer ()
  "Command: Ask the agent to summarize the current buffer."
  (interactive)
  (org-agent-run-command :summarize-buffer))

(defun org-agent-run-command (command-type)
  "Generic runner for high-level COMMAND-TYPE."
  (unless org-agent--network-process
    (org-agent-connect))
  (let ((ast (org-agent--buffer-to-sexp)))
    (org-agent-send 
     `(:type :EVENT 
       :payload (:sensor :user-command 
                 :command ,command-type
                 :file ,(buffer-file-name)
                 :ast ,ast)))
    (message "org-agent: Requesting '%s'..." command-type)))

;;;###autoload
(define-minor-mode org-agent-mode
  "Global minor mode for the org-agent Neurosymbolic kernel.
When enabled, this mode starts the Lisp daemon (if configured)
and establishes the network connection to enable proactive
Org-mode sensing."
  :global t
  :group 'org-agent
  (if org-agent-mode
      (progn
        (add-hook 'after-save-hook #'org-agent-notify-save)
        (add-hook 'post-command-hook #'org-agent-notify-point)
        (add-hook 'kill-emacs-hook #'org-agent-disconnect)
        (org-agent-connect))
    (remove-hook 'after-save-hook #'org-agent-notify-save)
    (remove-hook 'post-command-hook #'org-agent-notify-point)
    (remove-hook 'kill-emacs-hook #'org-agent-disconnect)
    (org-agent-disconnect)))

(provide 'org-agent)
;;; org-agent.el ends here
