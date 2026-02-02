# core.bash

Internal core API for bash-local.

## Overview

This module implements the core synchronization logic between the shell
environment and the current working directory.

It tracks environment transitions while navigating the filesystem and
reconciles shell state accordingly by:
- Pruning elements from exited environments.
- Applying elements from newly entered environments.

The module is not intended to be called directly by users.

---

Environment transition model:

| From \ To | Outside | Child | Root |
|-----------|---------|-------|------|
| Outside   |   -     | Source scoped | Source scoped and local |
| Child     | Remove scoped |   -   | Source local |
| Root      | Remove scoped and local | Remove local |   -   |

---

Global state used by this module:

- `_BL_STATE_CURRENT_ENVIRONMENTS`:
List of environments active for the current PWD.

- `_BL_STATE_PREVIOUS_ENVIRONMENTS`:
List of environments active for the previous PWD.

- `_BL_STATE[PPD]`:
Previous working directory.

## Index

* [_bl_core_refresh_current_environments_state](#_bl_core_refresh_current_environments_state)
* [_bl_core_refresh_environments_state](#_bl_core_refresh_environments_state)
* [_bl_core_collect_elements](#_bl_core_collect_elements)
* [_bl_core_resolve_prunable_elements](#_bl_core_resolve_prunable_elements)
* [_bl_core_remove_elements](#_bl_core_remove_elements)
* [_bl_core_prune_environments](#_bl_core_prune_environments)
* [_bl_core_collect_files](#_bl_core_collect_files)
* [_bl_core_resolve_applicable_environments](#_bl_core_resolve_applicable_environments)
* [_bl_core_source_files](#_bl_core_source_files)
* [_bl_core_apply_environments](#_bl_core_apply_environments)
* [_bl_core_sync](#_bl_core_sync)

## Environment state tracking

Functions in this section maintain the current and previous environment sets
derived from the working directory.

### _bl_core_refresh_current_environments_state

Computes the set of active environments for the current `PWD`.

An environment is considered active if a `bl/` directory exists in the path
hierarchy between `PWD` and `HOME`.

The function does nothing but clear current environments state if `PWD` is not
inside `HOME` directory.

Side effects:
- Writes: `_BL_STATE_CURRENT_ENVIRONMENTS`

_Function has no arguments._

#### See also

* Used in [_bl_core_refresh_environments_state](#_bl_core_refresh_environments_state)

### _bl_core_refresh_environments_state

Updates the environment state by shifting the current environments
to the previous set and recomputing the current ones.

This function must be called once per directory change before any pruning or
applying logic is executed.

Side effects:
- Reads: `_BL_STATE_CURRENT_ENVIRONMENTS`
- Writes: `_BL_STATE_PREVIOUS_ENVIRONMENTS`

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Prune stage

Functions in this section determine which shell elements must be removed when
environments are exited as a result of directory transitions.

### _bl_core_collect_elements

Collects prunable shell elements from an environment manifest.

Depending on the provided flags, local and/or scoped elements are extracted
from the environment's manifest file and appended to the given arrays.

If neither local nor scoped elements are requested, the function is a no-op.

#### Arguments

* **$1** (string): Environment path.
* **$2** (bool): Whether to collect local elements.
* **$3** (bool): Whether to collect scoped elements.
* **$4** (array): Reference to aliases array.
* **$5** (array): Reference to functions array.
* **$6** (array): Reference to variables array.

#### See also

* Used in [_bl_core_resolve_prunable_elements](#_bl_core_resolve_prunable_elements)

### _bl_core_resolve_prunable_elements

Determines which shell elements must be removed based on
environment transitions.

Elements are selected according to transitions between the previous and
current environment sets (Outside / Child / Root).

Only environments that are no longer active or have changed role are
considered prunable.

#### Arguments

* **$1** (array): Reference to aliases array.
* **$2** (array): Reference to functions array.
* **$3** (array): Reference to variables array.

#### See also

* Used in [_bl_core_prune_environments](#_bl_core_prune_environments)

### _bl_core_remove_elements

Removes shell elements from the current shell session.

Aliases, functions, and variables are removed silently if they exist.
Missing elements are ignored.

Side effects:
- Modifies shell state.

#### Arguments

* **$1** (array): Constant reference to aliases array.
* **$2** (array): Constant reference to functions array.
* **$3** (array): Constant reference to variables array.

#### See also

* Used in [_bl_core_prune_environments](#_bl_core_prune_environments)

### _bl_core_prune_environments

Prunes exited environments by removing their shell elements.

The function determines prunable environments based on the previous and
current environment state and removes their scoped and/or local elements
accordingly.

If the previous directory (`PPD`) is outside `$HOME`, the function is a no-op.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Apply stage

Functions in this section determine which environment files must be sourced
when entering new environments.

### _bl_core_collect_files

Collects source files from an environment.

Depending on the provided flags, local and/or scoped source files are appended
to the given files array.

#### Arguments

* **$1** (string): Environment path.
* **$2** (bool): Whether to collect the local source file.
* **$3** (bool): Whether to collect the scoped source file.
* **$4** (array): Reference to files array.

#### See also

* Used in [_bl_core_resolve_applicable_environments](#_bl_core_resolve_applicable_environments)

### _bl_core_resolve_applicable_environments

Determines which environment files must be sourced based on
environment transitions.

Files are selected according to transitions between the previous and current
environment sets (Outside / Child / Root).

#### Arguments

* **$1** (array): Reference to files array.

#### See also

* Used in [_bl_core_apply_environments](#_bl_core_apply_environments)

### _bl_core_source_files

Sources environment files into the current shell session.

Files are sourced in the order they appear in the provided array.

Side effects:
- Executes shell code.

#### Arguments

* **$1** (array): Constant reference to files array.

#### See also

* Used in [_bl_core_apply_environments](#_bl_core_apply_environments)

### _bl_core_apply_environments

Applies newly entered environments by sourcing their files.

The function determines applicable environments based on the current
environment state and sources their scoped and/or local files accordingly.

If `PWD` is outside `$HOME`, the function is a no-op.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Environment synchronization

High-level synchronization entry point combining state refresh, pruning, and
application stages.

### _bl_core_sync

Synchronizes shell state with the current working directory.

This function:
1. Refreshes environment state.
2. Prunes exited environments.
3. Applies newly entered environments.

It is intended to be invoked from the directory change hook.

_Function has no arguments._

#### See also

* Used in [hook.sh](./hook.md#cd)

