import * as core from '@actions/core'

export function getExporters(input: string): ExportFunc[] {
  const targets = input.split(',')
  const exporters = new Array<ExportFunc>()
  for (const target of targets) {
    switch (target) {
      case 'log':
        exporters.push(exportLog)
        break
      case 'env':
        exporters.push(core.exportVariable)
        break
      case 'output':
        exporters.push(core.setOutput)
        break
      default:
        throw new Error(`Unexpected export type: ${target}`)
    }
  }
  return exporters
}

export type ExportFunc = (name: string, val: string) => void

export function exportLog(name: string, val: string): void {
  core.info(`export ${name}: ${val}`)
}
