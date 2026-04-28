(in-package :opencortex)

(defparameter *skill-gateway-manager*
  '(:name "gateway-manager"
    :description "Manages connections to external chat platforms."
    :capabilities (:link-gateway :list-gateways)
    :type :deterministic)
  "Skill metadata for the Gateway Manager.")

(defvar *gateways* nil "The internal registry of configured gateways.")

(defun save-gateways ()
  "Persist gateway metadata to XDG Config directory."
  (let ((path (merge-pathnames "gateways.lisp" (get-oc-config-dir))))
    (ensure-directories-exist path)
    (with-open-file (s path :direction :output :if-exists :supersede)
      (format s ";;; OpenCortex Gateway Registry~%~s~%" *gateways*))))

(defun skill-gateway-register (platform metadata)
  "Internal function to update the gateway registry."
  (setf (getf *gateways* platform) metadata))

(defun skill-gateway-verify-telegram (token)
  "Verifies a Telegram bot token via the getMe API."
  (let ((url (format nil "https://api.telegram.org/bot~a/getMe" token)))
    (handler-case
        (let* ((response (dex:get url))
               (data (cl-json:decode-json-from-string response)))
          (if (cdr (assoc :ok data))
              (let ((result (cdr (assoc :result data))))
                (list :status :verified :username (cdr (assoc :username result))))
              (list :status :failed :error "Invalid Token")))
      (error (c) (list :status :failed :error (format nil "~a" c))))))

(defun skill-gateway-link (platform token)
  "Primary capability to link a new platform. Returns status plist."
  (harness-log "GATEWAY: Attempting to link ~a..." platform)
  (let ((verification (cond 
                        ((eq platform :telegram) (skill-gateway-verify-telegram token))
                        (t (list :status :verified :info "Platform verification pending implementation")))))
    (if (eq (getf verification :status) :verified)
        (progn
          (save-secret platform :token token)
          (skill-gateway-register platform verification)
          (save-gateways)
          (list :status :success :platform platform :info verification))
        (list :status :error :reason (getf verification :error)))))

(defun gateway-manager-main (platform token)
  "Main entry point for CLI-driven linkage."
  (if (and platform token)
      (let ((result (skill-gateway-link (intern (string-upcase platform) :keyword) token)))
        (format t "RESULT: ~s~%" result)
        (uiop:quit 0))
      (progn
        (format t "Usage: opencortex link <PLATFORM> <TOKEN>~%")
        (uiop:quit 1))))
