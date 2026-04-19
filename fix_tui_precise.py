import sys

filepath = 'literate/tui-client.org'
with open(filepath, 'r') as f:
    lines = f.read()

# I will replace the block from (defun listen-thread to (sleep 0.05)))
# with a guaranteed balanced version.

import re
pattern = r'\(defun listen-thread \(.*?\)\s+\(sleep 0.05\)\)\)'
replacement = """(defun listen-thread ()
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

# We use a more aggressive regex that matches greedily to consume all duplication
lines = re.sub(r'\(defun listen-thread \(.*?\)\s+\(sleep 0.05\)\)\).*?\(sleep 0.05\)\)\)', replacement, lines, flags=re.DOTALL)

with open(filepath, 'w') as f:
    f.write(lines)
print("Precise repair applied.")
