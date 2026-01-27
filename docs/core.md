# core.sh

Reconciles the active environments with the current directory by

## Overview

Contains all the functions needed to synchronize the bash-local
environments with the current directory. Not intended to be called directly by
users.
-----------------------------------------------------------------------------

## Index

* [_bl_core_refresh_current_environments_file](#blcorerefreshcurrentenvironmentsfile)
* [_bl_core_refresh_environments_files](#blcorerefreshenvironmentsfiles)
* [_bl_core_get_old_environments](#blcoregetoldenvironments)
* [_bl_core_get_new_environments](#blcoregetnewenvironments)
* [_bl_core_collect_elements](#blcorecollectelements)
* [_bl_core_remove_elements](#blcoreremoveelements)
* [_bl_core_unload_environments](#blcoreunloadenvironments)
* [_bl_core_sync](#blcoresync)

## Environments' files

Environments' files are used to store the current and previous
environments between 'cd' executions. They are located in '_BL_STATE[TMP_DIR]'
and must be refreshed on each execution.

Note that 'current' and 'previous' describe absolute environment sets
(i.e. the full environments active at a given directory state) and
'old' and 'new' describe relative ones, representing environments to be
removed from or added to the current state when transitioning between
directories.
-----------------------------------------------------------------------------

### _bl_core_refresh_current_environments_file

Does it by searching a '.bl' directory in PWD (Path Working
Directory) parents and storing them in the CURRENT_ENVIRONMENTS_FILE. The
function does nothing but clear the file if the PWD (Path Working Directory)
is not inside the HOME directory.

_Function has no arguments._

#### See also

* [_bl_core_refresh_environments_files()](#blcorerefreshenvironmentsfiles)

### _bl_core_refresh_environments_files

Sets the current environments as previous by swapping the files'
variables and calculates the current ones.

_Function has no arguments._

#### See also

* [_bl_core_sync()](#blcoresync)

### _bl_core_get_old_environments

#### Arguments

* **$1** (array): Reference to the old environments' array.

#### See also

* [_bl_core_unload_environments()](#blcoreunloadenvironments)

### _bl_core_get_new_environments

#### Arguments

* **$1** (array): Reference to the new environments' array.

#### See also

* [_bl_core_load_environments()](#blcoreloadenvironments)

## Unload stage

Old environments are unloaded at every 'cd' execution (i.e.
all the elements from each old environment are removed).
Note that 'unload' refers to an enviroment and 'remove' to an element.
-----------------------------------------------------------------------------

### _bl_core_collect_elements

A list of these elements is stored at the 'manifest' file located
inside each environment's '.bl' directory. This function reads the manifests
in order to get the aliases, functions and variables.

#### Arguments

* **$1** (array): Constant reference to the old environments' array.
* **$2** (array): Reference to the aliases' array.
* **$3** (array): Reference to the functions' array.
* **$4** (array): Reference to the variables' array.

#### See also

* [_bl_core_unload_environments()](#blcoreunloadenvironments)

### _bl_core_remove_elements

#### Arguments

* **$1** (array): Constant reference to the aliases' array.
* **$2** (array): Constant reference to the functions' array.
* **$3** (array): Constant reference to the variables' array.

#### See also

* [_bl_core_unload_environments()](#blcoreunloadenvironments)

### _bl_core_unload_environments

The function does nothing if the PPD (Path Previous Directory) is
not inside the HOME directory.

_Function has no arguments._

#### See also

* [_bl_core_sync()](#blcoresync)

## Environment synchronization

New environments are loaded at every 'cd' execution (i.e.
all the elements from each new environment are added).
Note that 'load' refers to an enviroment and 'add' to an element.
-----------------------------------------------------------------------------

### _bl_core_sync

_Function has no arguments._

#### See also

* [hook.sh](#hooksh)

