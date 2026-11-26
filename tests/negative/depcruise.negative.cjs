module.exports = {
  forbidden: [
    {
      name: 'B4-renderer-no-node',
      severity: 'error',
      from: { path: '^tests/negative' },
      to: { path: '^(node:|fs$)' },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsPreCompilationDeps: true,
  },
}
