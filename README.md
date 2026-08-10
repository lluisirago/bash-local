# bash-local

**bash-local** lets you define *directory-aware Bash environments* (aliases, functions, and variables) without replacing your global shell setup.

Each project can have its own environment that is:

- **Fast** - runs in ~40–50 µs per `cd`.
- **Composable** - environments can be nested.
- **Lightweight** - pure Bash, no daemons, no external binaries.

bash-local coexists with your regular Bash environment and activates
automatically when you move across directories.

---

## Concepts (read this first)

bash-local is built around **environment scopes**:

| Scope | Visibility |
|------|------------|
| **local**  | Only in the directory where it is defined (root) |
| **scoped** | In the directory and all its child directories |

And **environment transitions**:

- Entering a directory: apply environment
- Leaving a directory: clean environment
- Moving between nested environments: reconcile both

You never need to "enable" or "disable" anything manually.

---

## Installation

### 1. Clone the repository.
Run the following command in your terminal:

```bash
git clone https://github.com/lluisirago/bash-local.git
```

### 2. Enable bash-local in `~/.bashrc`
Add this line at the end of your `~/.bashrc` (adjust the path if needed):
```bash
[ -r "bash-local/usr/share/bash-local/bash-local" ] && source "bash-local/usr/share/bash-local/bash-local"
```

This will enable `bash-local` automatically every time you start a new terminal session.

## Basic usage

### 1. Initialize an environment

Inside any directory:
```bash
bl-init
```

This creates a `.bl/` directory containing:
```
.bl/
├── manifest
└── source/
    ├── local
    └── scoped
```

### 2. Define environment elements

There are **two steps**, always:

#### Step 1 - Define the element
- Local elements: `.bl/source/local`
- Scoped elements: `.bl/source/scoped`

#### Step 2 - Declare the element
Add its *name* to the appropriate section in `.bl/manifest`.

## Examples

### Example 1. Local alias (root only)

```bash
mkdir -p project/child
cd project
bl-init
```

**Define the alias** in `.bl/source/local`:
```bash
alias hello='echo "world"'
```

**Declare it** in `.bl/manifest`:
```
[local.aliases]
hello
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
[scoped.variables]
```

#### Result
```
~$ hello
Command 'hello' not found.

~$ cd project
~/project$ hello
world

~/project$ cd child
~/project/child$ hello
Command 'hello' not found.
```

### Example 2. Scoped function (root + children)

```bash
mkdir -p project/child
cd project
bl-init
```

**Define the function** in `.bl/source/scoped`:
```bash
foo() { 
    echo "This function is scoped"
}
```

**Declare it** in `.bl/manifest`:
```
[local.aliases]
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
foo
[scoped.variables]
```

#### Result
```
~$ cd project
~/project$ foo
This function is scoped

~/project$ cd child
~/project/child$ foo
This function is scoped

~/project/child$ cd
~$ foo
Command 'foo' not found.
```

### Example 3. Nested environments
```bash
mkdir -p work/frontend work/backend
cd work
bl-init
cd frontend
bl-init
cd ../backend
bl-init
```

**Define a shared variable** in `work/.bl/source/scoped`:
```bash
version="1.1.0"
```

**Declare it** in `work/.bl/manifest`:
```
[local.aliases]
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
[scoped.variables]
version
```

**Define a backend-only alias** in `work/backend/.bl/source/local`:
```bash
alias tool='echo "Executing tool..."'
```

**Declare it** in `work/backend/.bl/manifest`:
```
[local.aliases]
tool
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
[scoped.variables]
```

#### Result

```
~$ cd work
~/work$ echo "$version"
1.1.0
~/work$ tool
Command 'tool' not found.

~/work$ cd backend
~/work/backend$ echo "$version"
1.1.0
~/work/backend$ tool
Executing tool..

~/work/backend$ cd ../frontend
~/work/frontend$ echo "$version"
1.1.0
~/work/frontend$ tool
Command 'tool' not found.
```

## Performance
bash-local is designed to be **unnoticeable**:
- **~40-50 µs per `cd`.**
- Pure Bash.
- No `fork`, no `exec`, no background processes.

### Comparison (typical)

| Tool | Implementation | `cd` cost |
|------|----------------|-----------|
| bash-local  | pure Bash | **~0.05 ms** |
| direnv  | external binary | ~5-30 ms |
| autoenv  | shell + eval | ~10-30 ms |

## Documentation

- User documentation: this README
- Internal documentation: [`docs/`](./docs/index.md)

## State of development

Development is focused on version 1 on `develop` branch.

The core behavior and performance characteristics are considered stable.



```
 _              _        _                _
| |__  __ _ ___| |__    | | ___  ___ __ _| |
| '_ \/ _` / __| '_ \ __| |/ _ \/ _ / _` | |
| |_) )(_| \__ \ | | |__| | (_)( (_( (_| | |
|_.__/\__,_|___/_| |_|  |_|\___/\___\__,_|_|
```