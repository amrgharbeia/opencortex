(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(push (truename "./") asdf:*central-registry*)
(ql:quickload :opencortex)

;; Manually load .env for testing
(with-open-file (in ".env" :if-does-not-exist nil)
  (when in
    (loop for line = (read-line in nil) while line do
      (let ((pos (position #\= line)))
        (when pos
          (let ((key (string-trim " \"" (subseq line 0 pos)))
                (val (string-trim " \"" (subseq line (1+ pos)))))
            (sb-posix:putenv (format nil "~a=~a" key val))))))))

(opencortex:initialize-all-skills)

(format t "~%--- PROBING OPENROUTER ---~%")
;; Inject it directly into the vault memory to be sure
(let ((key (uiop:getenv "OPENROUTER_API_KEY")))
  (when key
    (setf (gethash "OPENROUTER-API-KEY" opencortex::*vault-memory*) key)))

(let ((res (opencortex:ask-probabilistic "Say Cognitive Loop Active" :cascade (list :openrouter))))
  (format t "~%--- PROBE RESULT ---~%~s~%--------------------~%" res)
  (if (and (stringp res) (search "Active" res))
      (uiop:quit 0)
      (uiop:quit 1)))
