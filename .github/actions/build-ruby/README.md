
# Install Node

Using Homebrew, install Node (npm will be installed with Node):

```
brew install node
```

# Install Yarn

Yarn provides dependency management, so install it:

```
brew install yarn
```

# Install NCC

NCC is used to compile the *.js into a dist/index.js

```
npm i -g @zeit/ncc
```

# Build the dist/index.js

```
yarn run package
```

# Optional pre-commit hook

A pre-commit hook is provided that can help keep dist/index.js in tune with local changes

