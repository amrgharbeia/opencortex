(in-package :org-agent)

(defparameter *safety-whitelist*
  '(;; Math & Logic
    + - * / = < > <= >= 1+ 1- min max
    and or not null eq eql equal string= string-equal
    ;; List Manipulation
    list cons car cdr cadr cddr cdar caar append mapcar remove-if remove-if-not
    length reverse sort nth nthcdr push pop
    ;; Plists and Hash Tables
    getf gethash
    ;; Control Flow
    let let* if cond when unless case typecase
    ;; Strings
    format concatenate string-downcase string-upcase search
    ;; Kernel specifics
    org-agent::harness-log
    org-agent::snapshot-object-store
    org-agent::rollback-object-store
    org-agent::lookup-object
    org-agent::list-objects-by-type
    org-agent::ingest-ast
    org-agent::find-headline-missing-id
    org-agent::context-query-store
    org-agent::context-get-active-projects
    org-agent::context-get-recent-completed-tasks
    org-agent::context-list-all-skills
    org-agent::context-get-system-logs
    org-agent::context-assemble-global-awareness
    org-agent::org-object-id
    org-agent::org-object-type
    org-agent::org-object-attributes
    org-agent::org-object-content
    org-agent::org-object-parent-id
    org-agent::org-object-children
    org-agent::org-object-version
    org-agent::org-object-last-sync
    org-agent::org-object-hash
    ;; Essential macros
    declare ignore
    ;; Let's also add simple data types
    t nil quote function))
