import {ExportFunc} from './exporter'
import Ajv from 'ajv'

class KeyVariablesPair {
  key: string
  variables: Map<string, string>
  idx: number

  constructor(key: string, variables: Map<string, string>, idx: number) {
    this.key = key
    this.variables = variables
    this.idx = idx
  }

  match(key: string): boolean {
    return Boolean(key.match(this.key))
  }

  export(fn: ExportFunc): void {
    for (const variable of this.variables.entries()) {
      fn(variable[0], variable[1])
    }
  }

  merge(kvp: KeyVariablesPair): void {
    this.variables = new Map([
      ...this.variables.entries(),
      ...kvp.variables.entries()
    ])
    this.key = `${this.key}\n${kvp.key}`
  }
}

interface Matcher {
  match(key: string, pairs: KeyVariablesPair[]): KeyVariablesPair | undefined
}

class FirstMatch implements Matcher {
  match(key: string, pairs: KeyVariablesPair[]): KeyVariablesPair | undefined {
    for (const param of pairs) {
      const ok = param.match(key)
      if (ok) {
        return param
      }
    }
  }
}

class Overwrite implements Matcher {
  match(key: string, pairs: KeyVariablesPair[]): KeyVariablesPair | undefined {
    let pair: KeyVariablesPair | undefined
    for (const param of pairs) {
      const ok = param.match(key)
      if (ok) {
        if (pair === undefined) {
          pair = param
          continue
        }
        pair.merge(param)
      }
    }
    return pair
  }
}

class Fill implements Matcher {
  match(key: string, pairs: KeyVariablesPair[]): KeyVariablesPair | undefined {
    let pair: KeyVariablesPair | undefined
    for (const param of pairs.reverse()) {
      const ok = param.match(key)
      if (ok) {
        if (pair === undefined) {
          pair = param
          continue
        }
        pair.merge(param)
      }
    }
    return pair
  }
}

abstract class Mapper {
  static schema = {
    type: 'object',
    additionalProperties: {
      type: 'object',
      additionalProperties: {type: 'string'}
    }
  }

  protected validate(input: object): void {
    const ajv = new Ajv()
    const valid = ajv.validate(Mapper.schema, input)
    if (!valid) throw new Error(`Validation failed: ${ajv.errorsText()}`)
  }
  abstract matcher: Matcher
  abstract pairs: KeyVariablesPair[]
  match(key: string): KeyVariablesPair | undefined {
    return this.matcher.match(key, this.pairs)
  }
}

export class JSONMapper extends Mapper {
  pairs: KeyVariablesPair[]
  matcher: Matcher

  constructor(rawJSON: string, mode: string) {
    super()

    switch (mode) {
      case 'first_match':
        this.matcher = new FirstMatch()
        break
      case 'overwrite':
        this.matcher = new Overwrite()
        break
      case 'fill':
        this.matcher = new Fill()
        break
      default:
        throw new Error(`Unexpected mode: ${mode}`)
    }

    const parsed = JSON.parse(rawJSON)
    this.validate(parsed as object)

    const tmpPairs = new Array<KeyVariablesPair>()
    const minify = rawJSON.replace(/\s/g, '')
    for (const key in parsed) {
      const json_key = JSON.stringify(key)
      //Gets the position of the input keys to keep their order.
      const idx = minify.indexOf(`${json_key}:{`)
      if (idx === -1) {
        throw new Error(`Failed to get key index of ${key}`)
      }
      const values = new Map<string, string>()
      for (const val in parsed[key]) {
        values.set(val, parsed[key][val])
      }
      const p = new KeyVariablesPair(key, values, idx)
      tmpPairs.push(p)
    }

    this.pairs = tmpPairs.sort(function (a, b) {
      return a.idx - b.idx
    })
  }
}
