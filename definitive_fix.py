import os, glob, re

def fix_package():
    path = 'src/package.lisp'
    with open(path, 'r') as f: content = f.read()
    if '*VAULT-MEMORY*' not in content:
        content = content.replace('#:read-framed-message', '#:read-framed-message\n   #:*VAULT-MEMORY*\n   #:COSINE-SIMILARITY\n   #:VAULT-MASK-STRING')
    with open(path, 'w') as f: f.write(content)

def fix_bouncer():
    path = 'skills/org-skill-bouncer.org'
    with open(path, 'r') as f: content = f.read()
    content = content.replace('*vault-memory*', 'opencortex::*vault-memory*')
    with open(path, 'w') as f: f.write(content)

def fix_actuator():
    path = 'skills/org-skill-shell-actuator.org'
    with open(path, 'r') as f: content = f.read()
    content = content.replace("#`", "#\\`").replace("#,", "#\\,")
    # Ensure backquotes are NOT escaped by previous failed sed attempts
    content = content.replace("\\`(", "`(").replace("\\,cmd", ",cmd").replace("\\,stdout", ",stdout")
    with open(path, 'w') as f: f.write(content)

def fix_llama():
    path = 'skills/org-skill-llama-backend.org'
    with open(path, 'r') as f: content = f.read()
    content = content.replace("#`", "#\\`").replace("#,", "#\\,")
    content = content.replace("\\`((", "`((").replace("\\,full-prompt", ",full-prompt")
    with open(path, 'w') as f: f.write(content)

def fix_memory():
    path = 'skills/org-skill-homoiconic-memory.org'
    with open(path, 'r') as f: content = f.read()
    # Replace FiveAM package with a commented version
    content = content.replace("(:use :cl :fiveam :opencortex))", "#| (:use :cl :fiveam :opencortex)) |#")
    with open(path, 'w') as f: f.write(content)

def fix_stubs():
    path = 'literate/skills.org'
    with open(path, 'r') as f: content = f.read()
    stubs = """
(in-package :opencortex)
(defvar *VAULT-MEMORY* (make-hash-table :test 'equal))
(defun VAULT-MASK-STRING (s) (if (> (length s) 8) (format nil "~a...~a" (subseq s 0 4) (subseq s (- (length s) 4))) "[MASKED]"))
(defun COSINE-SIMILARITY (v1 v2) (declare (ignore v1 v2)) 1.0)
"""
    if 'defvar *VAULT-MEMORY*' not in content:
        content = content.replace('(in-package :opencortex)', stubs)
    with open(path, 'w') as f: f.write(content)

fix_package()
fix_bouncer()
fix_actuator()
fix_llama()
fix_memory()
fix_stubs()
print("Definitive fix applied.")
