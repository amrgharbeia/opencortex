(in-package :org-agent)

(defvar *vault-memory* (make-hash-table :test 'equal)
  "In-memory cache of sensitive credentials.")

(defun vault-mask-string (str)
  "Returns a masked version of a sensitive string."
  (if (and str (> (length str) 8))
      (format nil "~a...~a" (subseq str 0 4) (subseq str (- (length str) 4)))
      "[REDACTED]"))

(defun vault-get-secret (provider &key (type :api-key))
  "Retrieves a credential. Type can be :api-key or :session."
  (let* ((key (format nil "~a-~a" provider type))
         (val (gethash key *vault-memory*)))
    (if val
        val
        ;; Fallback to environment
        (let ((env-var (case provider
                         ((:gemini :gemini-api) "GEMINI_API_KEY")
                         (:openai "OPENAI_API_KEY")
                         (:anthropic "ANTHROPIC_API_KEY")
                         (:groq "GROQ_API_KEY")
                         (:openrouter "OPENROUTER_API_KEY")
                         (:telegram "TELEGRAM_BOT_TOKEN")
                         (:signal "SIGNAL_ACCOUNT_NUMBER")
                         (:matrix-homeserver "MATRIX_HOMESERVER")
                         (:matrix-token "MATRIX_ACCESS_TOKEN")
                         (t nil))))
          (when (and env-var (eq type :api-key))
            (uiop:getenv env-var))))))

(defun vault-set-secret (provider secret &key (type :api-key))
  "Securely stores a secret and triggers a Merkle snapshot."
  (let ((key (format nil "~a-~a" provider type)))
    (setf (gethash key *vault-memory*) secret)
    (harness-log "VAULT - Updated ~a for ~a. Triggering Merkle snapshot..." type provider)
    (snapshot-object-store)
    t))

(defun vault-onboard-gemini-web ()
  "Instructions for the Sovereign Cookie Handshake."
  (harness-log "--- GEMINI WEB ONBOARDING ---")
  (harness-log "1. Visit gemini.google.com")
  (harness-log "2. Run the 'Get Gemini Cookies' Bookmarklet.")
  (harness-log "   CODE: javascript:(function(){const c=document.cookie.split('; ').reduce((r,v)=>{const [n,val]=v.split('=');r[n]=val;return r},{});const target=['__Secure-1PSID','__Secure-1PSIDTS'];const out=target.map(n=>({name:n,value:c[n]}));prompt('Copy JSON:',JSON.stringify(out));})();")
  (harness-log "PLATFORM GUIDE: Chrome/Firefox/Safari all support Bookmarklets via 'Add Page' or 'New Bookmark'.")
  t)

(progn
  (defskill :skill-credentials-vault
    :priority 200 ; High priority, foundational
    :trigger (lambda (ctx) (eq (getf (getf ctx :payload) :sensor) :onboarding-request))
    :neuro nil
    :symbolic (lambda (action ctx) 
                (vault-onboard-gemini-web)
                action)))
