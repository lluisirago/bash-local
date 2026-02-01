# core.bash

Internal core API.

## Overview

Contains all functions needed to synchronize bash-local
environments with current directory. Not intended to be called directly
by users.

Actions on each environment according to state:
| From \ To | Outside | Child | Root |
| - | - | - | - |
| **Outside** | - | Source scoped | Source scoped and local |
| **Child** | Remove scoped | - | Source local |
| **Root** | Remove scoped and local | Remove local | - |

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

## Environments' state

Calculates current environments by storing `PWD` parents with
`bl` directory.

The function does nothing but clear current environments state if `PWD` is not
inside `HOME` directory.

### _bl_core_refresh_current_environments_state

Calculates current environments by storing `PWD` parents with
`bl` directory.

The function does nothing but clear current environments state if `PWD` is not
inside `HOME` directory.

_Function has no arguments._

#### See also

* Used in [_bl_core_refresh_environments_state](#_bl_core_refresh_environments_state)

### _bl_core_refresh_environments_state

Updates previous and current environments (i.e. sets current
environments as previous and calculates current ones).

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Prune stage

Gets elements (local or scoped) from environment.

### _bl_core_collect_elements

Gets elements (local or scoped) from environment.

#### Arguments

* **$1** (string): Environment.
* **$2** (bool): Collect local elements.
* **$3** (bool): Collect scoped elements.
* **$4** (array): Reference to aliases' array.
* **$5** (array): Reference to functions' array.
* **$6** (array): Reference to variables' array.

#### See also

* Used in [_bl_core_resolve_prunable_elements](#_bl_core_resolve_prunable_elements)

### _bl_core_resolve_prunable_elements

Gets elements to remove. Only prunable environments will be
affected.

Elements to remove based on prunable environment:
- **Root** to **child**: local elements.
- **Child** to **outside**: scoped elements.
- **Root** to **outside**: local and scoped elements.

#### Arguments

* **$1** (array): Reference to aliases' array.
* **$2** (array): Reference to functions' array.
* **$3** (array): Reference to variables' array.

#### See also

* Used in [_bl_core_prune_environments](#_bl_core_prune_environments)

### _bl_core_remove_elements

Removes elements.

#### Arguments

* **$1** (array): Constant reference to aliases' array.
* **$2** (array): Constant reference to functions' array.
* **$3** (array): Constant reference to variables' array.

#### See also

* Used in [_bl_core_prune_environments](#_bl_core_prune_environments)

### _bl_core_prune_environments

Prunes environments based on element scope.

The function does nothing if `PPD` (Path Previous Directory) is not inside
`HOME` directory.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Apply stage

Gets file (local or scoped) from environment.

### _bl_core_collect_files

Gets file (local or scoped) from environment.

#### Arguments

* **$1** (string): Environment.
* **$2** (bool): Collect local file.
* **$3** (bool): Collect scoped file.
* **$4** (array): Reference to files' array.

#### See also

* Used in [_bl_core_resolve_applicable_environments](#_bl_core_resolve_applicable_environments)

### _bl_core_resolve_applicable_environments

Gets the files to source. Only applicable environments will be
affected.

File to source based on applicable environment:
- **Child** to **root**: local file.
- **Outside** to **child**: scoped file.
- **Outside** to **root**: local and scoped files.

#### Arguments

* **$1** (array): Reference to files' array.

#### See also

* Used in [_bl_core_apply_environments](#_bl_core_apply_environments)

### _bl_core_source_files

Sources files.

#### Arguments

* **$1** (array): Constant reference to files' array.

#### See also

* Used in [_bl_core_apply_environments](#_bl_core_apply_environments)

### _bl_core_apply_environments

Applies environments based on element scope.

The function does nothing if `PWD` is not inside `HOME` directory.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Environment synchronization

Reconciles active environments with current directory by
pruning exited environments and applying newly entered ones.

### _bl_core_sync

Reconciles active environments with current directory by
pruning exited environments and applying newly entered ones.

_Function has no arguments._

#### See also

* Used in [hook.md](./hook.sh#cd)

