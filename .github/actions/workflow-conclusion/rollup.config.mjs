import pluginCommonjs from '@rollup/plugin-commonjs';
import pluginJson from '@rollup/plugin-json';
import pluginNodeResolve from '@rollup/plugin-node-resolve';
import pluginTypescript from '@rollup/plugin-typescript';

export default {
  input: 'src/main.ts',
  output: {
    file: 'lib/main.js',
    format: 'cjs',
  },
  plugins: [
    pluginTypescript(),
    pluginNodeResolve(),
    pluginCommonjs(),
    pluginJson(),
  ],
};
