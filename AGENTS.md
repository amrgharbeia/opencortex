# Agent Guidelines for OpenCortex

## Critical Rule: Literate Programming Discipline

OpenCortex is a literate programming system. **All code lives in `.org` files.** The `.lisp` files in `library/gen/` and elsewhere are **generated build artifacts**.

### NEVER edit `.lisp` files directly.

If you edit a `.lisp` file directly:
- Your changes will be overwritten on next tangle
- The diff will be unreviewable  
- You violate the single source of truth principle

### ALWAYS edit `.org` files and regenerate.

## Tools Available

You have `emacs --batch` available. Use it for all org operations.

### Tangling (Regenerating `.lisp` from `.org`)

```bash
# Tangle a single org file
emacs --batch --load org --eval '(org-babel-tangle-file "path/to/file.org")'

# Or use the convenience script
~/.opencode/bin/tangle path/to/file.org
```

### Evaluating Src Blocks

```bash
# Evaluate all src blocks in an org file
emacs --batch --load org --eval '(setq org-confirm-babel-evaluate nil)' --eval '(org-babel-execute-buffer)'

# Or use the convenience script
~/.opencode/bin/org-eval path/to/file.org
```

### Checking Paren Balance

Before committing org changes, verify all lisp blocks have balanced parens:

```bash
~/.opencode/bin/org-balance-check path/to/file.org
```

## Workflow

1. **Identify the org source** - Find which `.org` file contains the block you need to modify
2. **Edit the org file** - Make changes in the `.org` file, not the `.lisp`
3. **Evaluate the block** - Use `org-eval` to verify the block compiles
4. **Tangle** - Use `tangle` to regenerate the `.lisp` file
5. **Verify balance** - Use `org-balance-check` to ensure no paren mismatches
6. **Test** - Load the system and run tests
7. **Commit the org file** - The `.lisp` is a generated artifact; the org is what matters

## Architecture Reminder

- `skills/*.org` - Skill definitions (the source of truth)
- `library/gen/*.lisp` - Generated from `skills/*.org` via tangle
- `harness/*.org` - Core harness code (also org sources)
- `library/*.lisp` - Generated from `harness/*.org` via tangle

## Common Mistakes to Avoid

1. **Editing `.lisp` directly** - This is the #1 mistake. Always fix org.
2. **Forgetting to tangle** - Changes in org don't affect `.lisp` until you tangle.
3. **Not evaluating blocks** - Use `C-c C-c` or `org-eval` to catch syntax errors early.
4. **Assuming no Emacs** - `emacs --batch` works perfectly for all org operations.

## Emergency: System Won't Load

If the system fails to load due to a broken `.lisp` file:

1. **Do not fix the `.lisp`**
2. Find the corresponding `.org` file
3. Fix the org source
4. Tangle to regenerate
5. If the org itself is broken, restore from git history and re-apply changes correctly

## Test Command

```bash
cd /home/user/memex/projects/opencortex
sbcl --non-interactive --load run-all-tests.lisp
```
