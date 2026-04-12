(in-package :org-agent)

(defun get-embedding (text)
  "Retrieves a vector representation of text via the configured neural provider."
  (let* ((auth (get-provider-auth :gemini)) (api-key (getf auth :api-key))
         (endpoint "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent"))
    (unless api-key (return-from get-embedding nil))
    (let* ((url (format nil "~a?key=~a" endpoint api-key)) (headers `(("Content-Type" . "application/json")))
           (body (cl-json:encode-json-to-string `((model . "models/text-embedding-004") (content . ((parts . ((text . ,text)))))))))
      (handler-case (let* ((response (dex:post url :headers headers :content body))
                           (json (cl-json:decode-json-from-string response)))
                      (cdr (assoc :values (cdr (assoc :embedding json)))))
        (error (c) (harness-log "EMBEDDING FAILURE: ~a" c) nil)))))

(defun dot-product (v1 v2) 
  "Calculates the dot product of two numerical vectors."
  (reduce #'+ (mapcar #'* v1 v2)))

(defun magnitude (v) 
  "Calculates the Euclidean magnitude of a numerical vector."
  (sqrt (reduce #'+ (mapcar (lambda (x) (* x x)) v))))

(defun cosine-similarity (v1 v2)
  "Calculates the semantic distance between two vectors."
  (let ((m1 (magnitude v1)) (m2 (magnitude v2))) (if (or (zerop m1) (zerop m2)) 0 (/ (dot-product v1 v2) (* m1 m2)))))

(defun find-most-similar (query-vector top-k)
  "Identifies the top-k most semantically related objects in the store."
  (let ((similarities nil))
    (maphash (lambda (id obj) (let ((vec (org-object-vector obj))) (when vec (push (cons (cosine-similarity query-vector vec) obj) similarities)))) *object-store*)
    (let ((sorted (sort similarities #'> :key #'car))) (subseq sorted 0 (min top-k (length sorted))))))
