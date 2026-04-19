import sys

filepath = "literate/tui-client.org"
with open(filepath, "r") as f:
    lines = f.readlines()

out = []
in_block = False
for line in lines:
    if ";; 3. Handle Keyboard Input" in line:
        in_block = True
        out.append(line)
        out.append("            (let* ((event (get-wide-event input-win))\n")
        out.append("                   (ch (and event (typep event 'event) (event-key event))))\n")
        out.append("              (when ch\n")
        out.append("                (cond\n")
        out.append("                  ((or (eq ch #\\Newline) (eq ch #\\Return))\n")
        out.append("                   (let ((cmd (coerce *input-buffer* 'string)))\n")
        out.append("                     (setf (fill-pointer *input-buffer*) 0)\n")
        out.append("                     (when (> (length cmd) 0)\n")
        out.append("                       (let ((framed (opencortex:frame-message (format nil \"~s\" (list :type :EVENT :payload (list :sensor :chat-message :text cmd))))))\n")
        out.append("                         (format *stream* \"~a\" framed)\n")
        out.append("                         (finish-output *stream*)))\n")
        out.append("                     (when (string= cmd \"/exit\") (setf *is-running* nil))))\n")
        out.append("                  ((or (eq ch :backspace) (eq ch #\\Backspace) (eq ch #\\Rubout) (eq ch #\\Del))\n")
        out.append("                   (when (> (length *input-buffer*) 0)\n")
        out.append("                     (decf (fill-pointer *input-buffer*))))\n")
        out.append("                  ((characterp ch)\n")
        out.append("                   (vector-push-extend ch *input-buffer*))))\n")
        continue
    if in_block:
        if "(clear input-win)" in line:
            in_block = False
            out.append(line)
        continue
    out.append(line)

with open(filepath, "w") as f:
    f.writelines(out)
print("Fix applied")
