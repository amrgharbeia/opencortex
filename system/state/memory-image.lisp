(in-package :opencortex)

(SETF (GETHASH "fake-hash-123" *HISTORY-STORE*)
        #S(ORG-OBJECT
           :ID "persist-test-1"
           :TYPE NIL
           :ATTRIBUTES NIL
           :CONTENT "Integrity Check"
           :VECTOR NIL
           :PARENT-ID NIL
           :CHILDREN NIL
           :VERSION NIL
           :LAST-SYNC NIL
           :HASH "fake-hash-123")) 
(SETF (GETHASH "persist-test-1" *MEMORY*)
        (GETHASH "fake-hash-123" *HISTORY-STORE*)) 