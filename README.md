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

Using Docker:

```sh
docker run --rm \
  --name mysite \
  -p 8080:8080 \
  -v ${PWD}:/src \
  -v ${HOME}/hugo_cache:/tmp/hugo_cache \
  hugomods/hugo:exts-non-root-0.145.0 \
  server -p 8080 --buildDrafts --buildFuture
```

Or with Hugo:

```
hugo serve --buildDrafts --buildFuture
```

The site will be served at http://localhost:1313

## Date of an article

Use `date -Iseconds` to set the date of an article before publishing it.
