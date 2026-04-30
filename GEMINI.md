# OpenCortex Agent Mandates

This file defines mandatory workflows and technical standards for the Gemini CLI agent operating within the OpenCortex environment. These mandates supersede general defaults.

## Lisp Integrity Mandates
- **Validation:** Before applying any change to a `.lisp` file or a Lisp block in an `.org` file, you MUST use `utils-lisp-validate` to ensure structural and semantic integrity.
- **Formatting:** All generated Lisp code MUST be piped through `utils-lisp-format` to maintain project-standard indentation before being saved.
- **Structural Editing:** When modifying complex Lisp forms (nested macros or large functions), prefer using `utils-lisp-structural-extract` and `utils-lisp-structural-wrap` to avoid manual parenthesis errors.
- **Verification:** For new or non-trivial logic, use `utils-lisp-eval` to test the behavior of the isolated S-expression in a live REPL environment before tangling.

## Literate Org Mandates
- **AST Integrity:** When modifying Org files, utilize `utils-org-set-property`, `utils-org-set-todo`, and `utils-org-add-headline` to manipulate the document structure programmatically whenever possible.
- **ID Management:** Every new headline intended for tracking or tangling MUST have a unique ID generated via `utils-org-generate-id`.

## Engineering Workflow
- **Commit-Before-Modify:** Verify the git state is clean before starting a multi-file refactor.
- **Tangle Sync:** After modifying any `.org` file, you MUST ensure the corresponding `.lisp` artifacts are tangled and in sync.
- **Validation:** Run the project-specific test suite (`sbcl --load opencortex.asd`) after every significant change to verify system stability.
