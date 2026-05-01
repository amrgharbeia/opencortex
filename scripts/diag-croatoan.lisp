(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(ql:quickload :croatoan :silent t)
(handler-case
    (croatoan:with-screen (scr)
      (format t "Screen height: ~s~%" (croatoan:height scr))
      (format t "Screen width: ~s~%" (croatoan:width scr))
      (finish-output))
  (error (c) (format t "Croatoan Error: ~a~%" c)))
(uiop:quit 0)
