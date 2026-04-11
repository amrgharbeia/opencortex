(in-package :org-agent)

(defun get-browser-bridge-path ()
  "Returns the absolute path to the Python browser bridge script."
  (let ((root (or (uiop:getenv "PROJECT_ROOT") (uiop:native-namestring (uiop:getcwd)))))
    (merge-pathnames "scripts/browser-bridge.py" (uiop:ensure-directory-pathname root))))

(defun execute-browser-command (args)
  "Invokes the Playwright Python bridge with the provided arguments."
  (let* ((script-path (get-browser-bridge-path))
         (json-input (cl-json:encode-json-to-string args)))
    (handler-case
        (let ((output (uiop:run-program (list "python3" (uiop:native-namestring script-path))
                                        :input (make-string-input-stream json-input)
                                        :output :string
                                        :error-output :string)))
          (cl-json:decode-json-from-string output))
      (error (c)
        (list :status "error" :message (format nil "Bridge Execution Failed: ~a" c))))))

(def-cognitive-tool :browser 
  "High-fidelity web browsing via Playwright (Chromium). Supports JS rendering."
  ((:url :type :string :description "The target URL")
   (:action :type :string :description "Action to perform: 'extract_text' or 'screenshot'")
   (:selector :type :string :description "Optional CSS selector (default: 'body')"))
  :body (lambda (args)
          (let ((result (execute-browser-command args)))
            (if (string= (cdr (assoc :status result)) "success")
                (or (cdr (assoc :content result))
                    (cdr (assoc :screenshot--base64 result))
                    "Success (no content returned)")
                (format nil "BROWSER ERROR: ~a" (cdr (assoc :message result)))))))

(defskill :skill-playwright
  :priority 150
  :trigger (lambda (ctx) (declare (ignore ctx)) nil) ; Passive tool provider
  :neuro nil
  :symbolic (lambda (action ctx) (declare (ignore ctx)) action))
