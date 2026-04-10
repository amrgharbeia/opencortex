(in-package :org-agent)

(defvar *provider-pain-table* (make-hash-table :test 'equal))

(defun token-accountant-record-pain (provider)
  "Marks a provider as 'pained' (failed). It will be de-prioritized."
  (setf (gethash provider *provider-pain-table*) (+ (get-universal-time) 600)) ; 10 min penalty
  (kernel-log "ACCOUNTANT - Provider ~a de-prioritized due to failure." provider))

(defun token-accountant-get-cascade (context)
  "Returns a dynamic list of providers, routing around pained ones. Uses standardized gateway keywords."
  (let ((all-providers '(:openrouter :groq :gemini-api :ollama))
        (healthy nil)
        (pained nil)
        (now (get-universal-time)))
    (dolist (p all-providers)
      (if (> (or (gethash p *provider-pain-table*) 0) now)
          (push p pained)
          (push p healthy)))
    (append (nreverse healthy) (nreverse pained))))

(defun token-accountant-get-model-for-provider (provider &optional context)
  "Returns the recommended model for the provider, prioritizing free/subsidized models. Updated April 2026."
  (let ((complexity (ignore-errors (uiop:symbol-call :org-agent.skills.org-skill-router :router-classify-complexity context))))
    (case provider
      (:openrouter
       (case complexity
         (:REASONING "meta-llama/llama-3.3-70b-instruct:free") ; High fidelity, zero cost
         (:COGNITION "qwen/qwen3.6-plus:free")               ; Latest interaction, zero cost
         (t "meta-llama/llama-3.2-3b-instruct:free")))       ; Ultra-fast reflex, zero cost
      (:groq
       (case complexity
         (:REASONING "llama-3.3-70b-versatile")
         (t "llama-3.1-8b-instant")))
      (:gemini-api
       "gemini-1.5-flash-latest")
      (t nil))))

(defun token-accountant-patch-kernel ()
  "Hot-patches the kernel's cascade and model selector to use our dynamic logic."
  (setf org-agent:*provider-cascade* #'token-accountant-get-cascade)
  (setf org-agent::*model-selector-fn* #'token-accountant-get-model-for-provider))
