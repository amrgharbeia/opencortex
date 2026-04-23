(defpackage :opencortex-emacs-edit-tests
  (:use :cl :fiveam :opencortex)
  (:export #:emacs-edit-suite))

(in-package :opencortex-emacs-edit-tests)

(def-suite emacs-edit-suite
  :description "Tests for Emacs Edit skill.")

(in-suite emacs-edit-suite)

(test id-generation
  (let ((id1 (emacs-edit-generate-id))
        (id2 (emacs-edit-generate-id)))
    (is (plusp (length id1)))
    (is (not (string= id1 id2)) ;; Likely unique
    (is (= 8 (length id1)))))

(test id-format
  (let ((formatted (emacs-edit-id-format "abc12345")))
    (is (search "id:" formatted))))

(test property-setter
  (let ((ast (list :type :headline
                  :properties (list :ID "id:test123" :TITLE "Test")
                  :contents nil)))
    (emacs-edit-set-property ast "id:test123" :STATUS "ACTIVE")
    (is (string= (getf (getf ast :properties) :STATUS) "ACTIVE"))))

(test todo-setter
  (let ((ast (list :type :headline
                  :properties (list :ID "id:todo001" :TITLE "Task")
                  :contents nil)))
    (emacs-edit-set-todo ast "id:todo001" "DONE")
    (is (string= (getf (getf ast :properties) :TODO) "DONE"))))

(test find-headline-by-id
  (let ((ast (list :type :document
                  :contents (list (list :type :headline
                                   :properties (list :ID "id:findme" :TITLE "Found")
                                   :contents nil)))))
    (let ((found (emacs-edit-find-headline-by-id ast "id:findme")))
    (is (not (null found)))
    (is (string= (getf (getf found :properties) :ID) "id:findme"))))