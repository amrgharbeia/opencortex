;; org-agent: Guix Environment Manifest
;; Usage: guix shell -m manifest.scm -- sbcl --eval ...

(specifications->manifest
 '("sbcl"
   "sbcl-cl-json"
   "sbcl-bordeaux-threads"
   "sbcl-usocket"
   "sbcl-dexador"
   "sbcl-cl-ppcre"
   "ripgrep"
   "git"
   "curl"
   "sqlite"))
