module.exports = {
  forbidden: [
    {
      name: 'B4-renderer-no-node',
      severity: 'error',
      comment: 'The renderer reaches the system only through the preload surface.',
      from: { path: '^apps/desktop/src/renderer' },
      to: { path: '^(node:|electron$|electron/)' },
    },
    {
      name: 'B4-renderer-no-main',
      severity: 'error',
      comment: 'The renderer must not import main or preload modules.',
      from: { path: '^apps/desktop/src/renderer' },
      to: { path: '^apps/desktop/src/(main|preload)' },
    },
    {
      name: 'B6-no-cycles',
      severity: 'error',
      comment: 'A cycle is a seam in the wrong place.',
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    exclude: { path: '(^|/)(node_modules|out|dist)/' },
    tsPreCompilationDeps: true,
    combinedDependencies: true,
  },
}
