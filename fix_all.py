import os, re

def rewrite_gateway():
    path = 'skills/org-skill-llm-gateway.org'
    with open(path, 'r') as f: content = f.read()
    # Force OpenRouter as the only internal provider for auto-thoughts
    content = content.replace(':openai', ':openrouter')
    content = content.replace('openrouter/auto', 'google/gemini-2.0-flash-001')
    with open(path, 'w') as f: f.write(content)

def rewrite_tui():
    path = 'literate/tui-client.org'
    # Complete, balanced listener that handles events, status, and chat
    new_listener = """(defun listen-thread ()
  (loop while *is-running* do
    (handler-case
        (when (and *stream* (open-stream-p *stream*))
          (let ((raw-msg (opencortex:read-framed-message *stream*)))
            (unless (member raw-msg '(:eof :error))
              (let* ((msg (clean-keywords raw-msg))
                     (type (or (getf msg :TYPE) (getf msg :type)))
                     (payload (or (getf msg :PAYLOAD) (getf msg :payload))))
                (cond ((eq type :EVENT)
                       (let ((action (or (getf payload :ACTION) (getf payload :action)))
                             (sensor (or (getf payload :SENSOR) (getf payload :sensor)))
                             (text (or (getf payload :TEXT) (getf payload :text) (getf payload :MESSAGE) (getf payload :message))))
                         (cond ((eq action :handshake) (setf *status-text* "Ready"))
                               (text (enqueue-msg (format nil "SYSTEM: ~a" text))))))
                      ((eq type :STATUS)
                       (setf *status-text* (format nil "[Scribe: ~a] [Gardener: ~a]" 
                                                   (or (getf msg :SCRIBE) (getf msg :scribe))
                                                   (or (getf msg :GARDENER) (getf msg :gardener)))))
                      ((eq type :CHAT)
                       (enqueue-msg (or (getf msg :TEXT) (getf msg :text))))
                      (t (harness-log "TUI: Ignored unknown type ~a" type))))))
            (when (eq raw-msg :eof) (setf *is-running* nil))
            (when (eq raw-msg :error) (setf *status-text* "Protocol Error"))))
      (error (c) (setf *status-text* (format nil "Net Error: ~a" c)) (setf *is-running* nil)))
    (sleep 0.05)))"""
    
    with open(path, 'r') as f: content = f.read()
    # Replace the old listener function cleanly
    content = re.sub(r'\(defun listen-thread \(.*?\)\)\)\)', new_listener, content, flags=re.DOTALL)
    with open(path, 'w') as f: f.write(content)

rewrite_gateway()
rewrite_tui()
print("Rewrite complete.")
