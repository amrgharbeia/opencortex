(in-package :opencortex)

(defvar *vault-memory* (make-hash-table :test 'equal)
  "In-memory cache of sensitive credentials.")

(defun vault-get-secret (provider &key (type :api-key))
  "Retrieves a credential from the vault or environment."
  (let* ((key (format nil "~a-~a" provider type))
         (val (gethash key *vault-memory*)))
    (if val
        val
        (let ((env-var (case provider
                          (:gemini "GEMINI_API_KEY")
                          (:openai "OPENAI_API_KEY")
                          (:anthropic "ANTHROPIC_API_KEY")
                          (:openrouter "OPENROUTER_API_KEY")
                          (otherwise nil))))
          (when env-var (uiop:getenv env-var))))))

(defun vault-set-secret (provider secret &key (type :api-key))
  "Stores a secret in the vault."
  (let ((key (format nil "~a-~a" provider type)))
    (setf (gethash key *vault-memory*) secret)))

(defskill :skill-credentials-vault
  :priority 600
  :trigger (lambda (ctx) (declare (ignore ctx)) nil))
