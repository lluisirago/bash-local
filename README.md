# bash-local

bash-local is a way to maintain a unique environment (aliases, functions, and variables) for each project in Linux. It coexists with the usual Bash environment.

The user can choose whether the elements added to the environment (aliases, functions, or variables) are available only in the directory where the environment is created (root) or also in its child directories.

## Install

### 1. Clone the repository.
Run the following command in your terminal:

```bash
git clone https://github.com/lluisirago/bash-local.git
```

### 2. Configure the script in your `~/.bashrc` file.
Add the following line at the end of your `~/.bashrc` file with the right path to the `bash-local` file:

```bash
[ -r "bash-local/usr/share/bash-local/bash-local" ] && source "bash-local/usr/share/bash-local/bash-local"
```

This will enable `bash-local` automatically every time you start a new terminal session.

## Use

### 1. Create the directory structure.

In any directory where you want to use `bash-local`, execute:
```bash
bl-init
```

### 2. Add elements to the environment.

- Elements to be accessed from child directories (**scoped**). Define them in the `.bl/source/scoped` file and add its names into the `.bl/manifest` file, in the `scoped` sections.
- Elements to be accessed only from root directory (**local**). Define them in the `.bl/source/local` file and add its names into the `.bl/manifest` file, in the `local` sections.

*See the [example](#Example) below*.

These elements will be set automatically when you change to the environment.

## Examples

### 1. Set a local alias

```bash
mkdir dir dir/child
cd dir
bl-init
```

Then, add the following line into `.bl/source/local` file:

```bash
alias hello='echo "world"'
```

Finally, declare the alias in the correspondent section at the `manifest`. The file will look as follows:
```
[local.aliases]
hello
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
[scoped.variables]
```

Save the changes and exit.

#### Result

Now, a new alias is set only in the `dir` directory. The terminal will behave like this: 

```
~$ hello
Command 'hello' not found.
~$ cd dir
~/dir$ hello
world
~/dir$ cd child
~/dir/child$ hello
Command 'hello' not found.
~/dir/child$ cd
~$ hello
Command 'hello' not found.
```

### 2. Set a scoped function

```bash
mkdir dir dir/child
cd dir
bl-init
```

Then, add the following into `.bl/source/scoped` file:

```bash
foo() { 
    echo "This is my first function"
}
```

Finally, declare the function in the correspondent section at the `manifest`. The file will look as follows:
```
[local.aliases]
[local.functions]
[local.variables]
[scoped.aliases]
[scoped.functions]
foo
[scoped.variables]
```

Save the changes and exit.

#### Result

Now, a new function is set in the `dir` directory and can also be used in `dir/child` directory. The terminal will behave like this: 

```
~$ foo
Command 'foo' not found.
~$ cd dir
~/dir$ foo
This is my first function
~/dir$ cd child
~/dir/child$ foo
This is my first function
~/dir/child$ cd
~$ foo
Command 'foo' not found.
```

## State of development

Development is now focused on version 1 on `develop` branch.
