import re

path = 'skills/org-skill-llm-gateway.org'
with open(path, 'r') as f:
    content = f.read()

# Definitive fix for the cloud provider block
cloud_pattern = r'\(handler-case\s+\(let\*\s+\(\(response\s+\(progn.*?\(error\s+\(c\)\s+\(list\s+:status\s+:error\s+:message\s+\(format\s+nil\s+\"LLM\s+Gateway\s+Failure\s+\(~a\):\s+~a\"\s+active-provider\s+c\)\)\)\)'
cloud_fixed = """(handler-case 
             (let* ((response (progn 
                                (harness-log "LLM DEBUG: Requesting ~a..." active-provider)
                                (dex:post endpoint :headers headers :content body :connect-timeout 10 :read-timeout 30)))
                    (json (cl-json:decode-json-from-string response)))
               (harness-log "LLM DEBUG: Raw Response: ~a" response)
               (let ((content (case active-provider
                                (:anthropic (get-nested json :content :text))
                                (:gemini-api (get-nested json :candidates :parts :text))
                                (t (get-nested json :choices :message :content)))))
                 (if content
                     (list :status :success :content content)
                     (list :status :error :message (format nil "Failed to parse ~a response structure." active-provider)))))
           (error (c) (list :status :error :message (format nil "LLM Gateway Failure (~a): ~a" active-provider c))))"""

# Definitive fix for the Ollama block
ollama_pattern = r'\(handler-case\s+\(let\*\s+\(\(response\s+\(dex:post.*?\(error\s+\(c\)\s+\(list\s+:status\s+:error\s+:message\s+\(format\s+nil\s+\"Ollama\s+Failure:\s+~a\"\s+c\)\)\)\)'
ollama_fixed = """(handler-case 
             (let* ((response (dex:post url :headers '(("Content-Type" . "application/json")) :content body :connect-timeout 5 :read-timeout 60))
                    (json (cl-json:decode-json-from-string response)))
               (list :status :success :content (cdr (assoc :response json))))
           (error (c) (list :status :error :message (format nil "Ollama Failure: ~a" c))))"""

content = re.sub(cloud_pattern, cloud_fixed, content, flags=re.DOTALL)
content = re.sub(ollama_pattern, ollama_fixed, content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)
print("Gateway syntax repaired.")
