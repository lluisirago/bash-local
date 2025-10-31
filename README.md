# bash-local

bash-local is a way to maintain a unique environment (aliases, functions, and variables) for each directory in Linux. It coexists with the usual Bash environment.

## Install

1. **Clone the repository.** Run the following command in your terminal:

```bash
git clone https://github.com/lluisirago/bash-local.git
```

2. **Configure the script in your `~/.bashrc` file.** Add the following line to the end of your `~/.bashrc` file with the right path to the `main.sh` file:

```bash
[ -r /path/to/bash-local/main.sh ] && source /path/to/bash-local/main.sh
```

This will enable `bash-local` automatically every time you start a new terminal session.

## Use

1. **Create a .bash-local directory.** In any directory where you want to use `bash-local`, execute:

```bash
mkdir .bash-local
```

2. **Create files within the `.bash-local` directory.** Change to the new directory and create as many `.bash-local` files as you wish, for example:

```bash
cd .bash-local
touch aliases.bash-local
```

These files will be sourced automatically when you change to the directory containing the `.bash-local` directory.

## Example

If you want to set a local alias in a directory called `dir`, execute:

```bash
cd dir
mkdir .bash-local
cd .bash-local
touch alias.bash-local
```

Then, add the following line to the `alias.bash-local` file:

```sh
alias hello='echo "world"'
```

Save the changes and restart the terminal.

### Result

Now, you have a new alias only in the `dir` directory. The terminal will behave like this: 

```
~$ hello
Command 'hello' not found.
~$ cd dir
~/dir$ hello
world
~/dir$ cd
~$ hello
Command 'hello' not found.
```

## State of development

Development is focused on version 1 in the `main` branch.
