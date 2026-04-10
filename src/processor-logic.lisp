(defun inbox-is-private-p (tags)
  (member "@personal" tags :test #'string-equal))

(defun inbox-is-archive-p (tags)
  (member "!archive" tags :test #'string-equal))

(defun neuro-skill-inbox-processor (context)
  (let* ((payload (getf context :payload))
         (content (getf payload :content))
         (tags (getf payload :tags))
         (is-archive (inbox-is-archive-p tags)))
    (ask-neuro content :system-prompt
      (format nil "You are the PSF Librarian. Your goal is to ENRICH this Org-mode capture.
RULES:
1. Create a '** Summary' sub-heading with a 1-sentence summary.
2. Create a '** Significance' sub-heading with a paragraph explaining why this matters to a Sovereign Lisp Machine and how it can be used.
3. ~:[~;~* ARCHIVE MODE: Extract the full text of the item into a '** Full Text' sub-heading, preserving Org-mode structure.~]
4. Return ONLY a Lisp plist with :summary :significance :full-text.
5. NO conversational filler." is-archive))))

(defun inbox-process-logic (action context)
  (declare (ignore action))
  (let* ((payload (getf context :payload))
         (sensor (getf payload :sensor)))
    (when (eq sensor :heartbeat)
      (let* ((base-dir (or (uiop:getenv "MEMEX_DIR") "/home/user/memex/"))
             (inbox-path (merge-pathnames "inbox.org" base-dir)))
        (org-agent:kernel-log "INBOX - Scanning ~a for migration..." (uiop:native-namestring inbox-path))
        ;; Physical move logic would go here using Org AST parsing
        '(:target :system :payload (:action :message :text "Inbox processing complete (Simulation)."))))))
