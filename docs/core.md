# core.sh

Internal core API.

## Overview

Contains all the functions needed to synchronize the bash-local
environments with the current directory. Not intended to be called directly
by users.

## Index

* [_bl_core_refresh_current_environments](#blcorerefreshcurrentenvironments)
* [_bl_core_refresh_environments](#blcorerefreshenvironments)
* [_bl_core_get_old_environments](#blcoregetoldenvironments)
* [_bl_core_get_new_environments](#blcoregetnewenvironments)
* [_bl_core_collect_elements](#blcorecollectelements)
* [_bl_core_remove_elements](#blcoreremoveelements)
* [_bl_core_unload_environments](#blcoreunloadenvironments)
* [_bl_core_sync](#blcoresync)

## Environments

Environments' arrays must be refreshed on each execution.

Note that *current* and *previous* describe the active environments at a
given directory state and *old* and *new* represent environments to be
removed from or added to the current state.

Also note that *unload* or *load* refers to an enviroment and *remove* or
*add* to an element.

### _bl_core_refresh_current_environments

Calculates the current environments.

Does it by searching a `.bl` directory in PWD (Path Working Directory)
parents and storing them in `_BL_STATE_CURRENT_ENVIRONMENTS`. The function
does nothing but clear the array if the PWD is not inside the HOME directory.

_Function has no arguments._

#### See also

* Used in [_bl_core_refresh_environments](#_bl_core_refresh_environments)

### _bl_core_refresh_environments

Updates the previous and current environments' arrays.
Sets the current environments as previous and calculates the current ones.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

### _bl_core_get_old_environments

Gets the previous environments which are not current.

#### Arguments

* **$1** (array): Reference to the old environments' array.

#### See also

* Used in [_bl_core_unload_environments](#_bl_core_unload_environments)

### _bl_core_get_new_environments

Gets the current environments which are not previous.

#### Arguments

* **$1** (array): Reference to the new environments' array.

#### See also

* Used in [_bl_core_load_environments](#_bl_core_load_environments)

### _bl_core_collect_elements

Gets all the elements from the old environments, filtered by
kind.

A list of these elements is stored at the `manifest` file located inside each
environment's `.bl` directory. This function reads the manifests in order to
get the aliases, functions and variables.

#### Arguments

* **$1** (array): Constant reference to the old environments' array.
* **$2** (array): Reference to the aliases' array.
* **$3** (array): Reference to the functions' array.
* **$4** (array): Reference to the variables' array.

#### See also

* Used in [_bl_core_unload_environments](#_bl_core_unload_environments)

## Unload stage

Old environments are unloaded at every `cd` execution (i.e.
all the elements from each old environment are removed).

### _bl_core_remove_elements

Removes the given elements.

#### Arguments

* **$1** (array): Constant reference to the aliases' array.
* **$2** (array): Constant reference to the functions' array.
* **$3** (array): Constant reference to the variables' array.

#### See also

* Used in [_bl_core_unload_environments](#_bl_core_unload_environments)

### _bl_core_unload_environments

Unloads the old environments (i.e. those exited at the `cd`
execution).

The function does nothing if the `PPD` (Path Previous Directory) is not inside
the `HOME` directory.

_Function has no arguments._

#### See also

* Used in [_bl_core_sync](#_bl_core_sync)

## Environment synchronization

New environments are loaded at every `cd` execution (i.e.
all the elements from each new environment are added).

### _bl_core_sync

Reconciles the active environments with the current directory by
unloading exited environments and loading newly entered ones.

_Function has no arguments._

#### See also

* Used in [hook.md](./hook.sh#cd)

