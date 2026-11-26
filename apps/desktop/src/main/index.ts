import { app, BrowserWindow } from 'electron'
import { join } from 'node:path'

const createWindow = (): void => {
  const window = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: join(__dirname, '../preload/index.js'),
      sandbox: true,
    },
  })

  void window.loadFile(join(__dirname, '../renderer/index.html'))
}

void app.whenReady().then(() => {
  createWindow()
})
