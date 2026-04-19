import sys

filepath = 'literate/context.org'
with open(filepath, 'r') as f:
    lines = f.readlines()

out = []
skip = False
for line in lines:
    if '(defun context-resolve-path (path-string)' in line:
        out.append('(defun context-resolve-path (path-string)\n')
        out.append('  "Expands environment variables and strips literal quotes from a path string."\n')
        out.append('  (let ((path (if (stringp path-string) \n')
        out.append('                  (string-trim \'(#\\" #\\\' #\\Space) path-string)\n')
        out.append('                  path-string)))\n')
        out.append('    (if (and (stringp path) (search "$" path))\n')
        out.append('        (let ((result path))\n')
        out.append('          (ppcre:do-register-groups (var-name) ("\\\\$([A-Za-z0-9_]+)" path)\n')
        out.append('            (let ((var-val (uiop:getenv var-name)))\n')
        out.append('              (when var-val\n')
        out.append('                (setf result (ppcre:regex-replace (format nil "\\\\$~a" var-name) result var-val)))))\n')
        out.append('          result)\n')
        out.append('        path)))\n')
        skip = True
        continue
    
    if skip:
        if 'path-string))' in line:
            skip = False
        continue
    
    out.append(line)

with open(filepath, 'w') as f:
    f.writelines(out)

# 2. Fix opencortex.sh
with open('opencortex.sh', 'r') as f:
    sh = f.read()
sh = sh.replace('[ ! -f "$SCRIPT_DIR/.env" ]', '[ ! -f "$SCRIPT_DIR/.env" ] && [ ! -f "$HOME/.local/share/opencortex/.env" ]')
with open('opencortex.sh', 'w') as f:
    f.write(sh)
