STOW CLONE
----------

## Introduction
This is a sample implementation of Stow for Windows, written in PowerShell, forked from [Stow](https://github.com/mattialancellotti/Stow).

## Usage
```powershell
stow.ps1 [-t <target-dir>] [-d <source-dir>] [-dotfile] -Stow/-Unstow pkg1, pkg2, ...
```
Unlike GNU Stow, this implementation creates **absolute symbolic links**.

When the `-dotfile` option is used, Stow replaces the leading `dot-` in link names with `.`.

- `target-dir` defaults to the parent directory of the current working directory.
- `source-dir` defaults to the current working directory.
- If neither `-Stow` nor `-Unstow` is specified, `-Stow` is used by default.

Stow attempts to fold links (similar to GNU Stow). However, if you do not want to fold links, you can append `~` to the folder name.

e.g.:
```txt
source-dir
├─alacritty
│  └─AppData
│      └─Roaming
│          └─alacritty
│              └─alacritty.toml
├─git
│  └─dot-gitignore
└─some-pkg
    └dot-sample~
        └dot-test
```
Run `stow.ps1 -t ~ -d source-dir -dotfile git, alacritty, some-pkg`
```
~
├─AppData
│      └─Roaming
│          └─alacritty -> source-dir\alacritty\AppData\Roaming\alacritty
├─.gitignore -> source-dir\git\dot-gitignore
└─.sample
    └.test -> source-dir\some-pkg\dot-sample~\dot-test
```
