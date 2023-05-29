# Gabriele Bartolini - Blog

## How to clone this repo 

This git repository contain the `congo` theme as a submodule, and need to be
cloned with the `--recursive` option:

```
git clone git@github.com:TamaraNocentini/gblog.git --recursive
```

Without that option, one can manually download the submodules with:

```
git submodule init
git submodule update
```

## Prerequisites

```
brew install hugo
```

## How to start the development server

```
hugo serve --buildDrafts
```

The site will be served at http://localhost:1313
