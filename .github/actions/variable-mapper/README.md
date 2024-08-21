# Github Action for mapping variables by a specific key

![build-test](https://github.com/kanga333/variable-mapper/workflows/build-test/badge.svg)

Variable-Mapper action maps variables by regular expressions.

- The map argument is a configuration in json format.
  - The top-level key in JSON is a regular expression condition. They are evaluated in order from the top.
  - The value is the key-value pair of variables to be exported.
- The key argument is the key to match the map.

## Sample Workflows

### Export variables corresponding to regular expression-matched keys

```yaml
on: [push]
name: Export variables corresponding to regular expression-matched keys
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: ./.github/actions/variable-mapper
      with:
        key: "${{github.base_ref}}"
        map: |
          {
            "master": {
              "environment": "production",
              "AWS_ACCESS_KEY_ID": "${{ secrets.PROD_AWS_ACCESS_KEY_ID }}",
              "AWS_SECRET_ACCESS_KEY": "${{ secrets.PROD_AWS_ACCESS_KEY_ID }}"
            },
            "staging": {
              "environment": "staging",
              "AWS_ACCESS_KEY_ID": "${{ secrets.STG_AWS_ACCESS_KEY_ID }}",
              "AWS_SECRET_ACCESS_KEY": "${{ secrets.STG_AWS_ACCESS_KEY_ID }}"
            },
            ".*": {
              "environment": "development",
              "AWS_ACCESS_KEY_ID": "${{ secrets.DEV_AWS_ACCESS_KEY_ID }}",
              "AWS_SECRET_ACCESS_KEY": "${{ secrets.DEV_AWS_ACCESS_KEY_ID }}"
            }
          }
    - name: Echo environment
      run: echo ${{ env.environment }}
```

The key is evaluated from the top and exports the first matched variables.

### Export variables to output and environment and log

```yaml
on: [push]
name: Export variables to output and environment and log
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: kanga333/variable-mapper@master
      id: export
      with:
        key: "${{github.base_ref}}"
        map: |
          {
            "master": {
              "environment": "production"
            },
            ".*": {
              "environment": "development"
            }
          }
        export_to: env,log,output
    - name: Echo environment and output
      run: |
        echo ${{ env.environment }}
        echo ${{ steps.export.outputs.environment }}
```

The variables can be exported to log, env and output. (Default is `log,env`)

### Switching the behavior of getting the variable

The `mode` option can be used to change the behavior of getting variables.
`first_match`, `overwrite` and `fill` are valid values.

#### first_match mode (default)

`first_match` evaluates the regular expression of a key in order from the top and gets the variable for the first key to be matched.

```yaml
on: [push]
name: Exporting variables in the first match
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: kanga333/variable-mapper@master
      id: export
      with:
        key: "first"
        map: |
          {
            "first": {
              "env1": "value1",
              "env2": "value2"
            },
            ".*": {
              "env1": "value1_overwrite",
              "env3": "value3"
            }
          }
        export_to: env
        mode: first_match
    - name: Echo environment and output
      run: |
        echo ${{ env.env1 }}
        echo ${{ env.env2 }}
        echo ${{ env.env3 }}
```

In this workflow, only `env1:value1` and `env2:value2` are exported as env.

#### overwrite mode

`overwrite` evaluates the regular expression of the keys in order from the top, and then merges the variables associated with the matched keys in turn. If the same variable is defined, the later evaluated value is overwritten.

```yaml
on: [push]
name: Exporting variables by overwriting
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: kanga333/variable-mapper@master
      id: export
      with:
        key: "first"
        map: |
          {
            "first": {
              "env1": "value1",
              "env2": "value2"
            },
            ".*": {
              "env1": "value1_overwrite",
              "env3": "value3"
            }
          }
        export_to: env
        mode: overwrite
    - name: Echo environment and output
      run: |
        echo ${{ env.env1 }}
        echo ${{ env.env2 }}
        echo ${{ env.env3 }}
```

In this workflow, `env1:value1_overwrite`, `env2:value2` and `env3:value3` export as env.

#### fill mode

`fill` evaluates the regular expression of the keys in order from the top, and then merges the variables associated with the matched keys in turn. If the same variable is defined, later evaluated values are ignored and the first evaluated value takes precedence.

```yaml
on: [push]
name: Export parameters in filling
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: kanga333/variable-mapper@master
      id: export
      with:
        key: "first"
        map: |
          {
            "first": {
              "env1": "value1",
              "env2": "value2"
            },
            ".*": {
              "env1": "value1_overwrite",
              "env3": "value3"
            }
          }
        export_to: env
        mode: fill
    - name: Echo environment and output
      run: |
        echo ${{ env.env1 }}
        echo ${{ env.env2 }}
        echo ${{ env.env3 }}
```

In this workflow, `env1:value1`, `env2:value2` and `env3:value3` export as env.
