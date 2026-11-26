import { contextBridge } from 'electron'

contextBridge.exposeInMainWorld('mavrykx', {
  version: '0.0.0',
})
