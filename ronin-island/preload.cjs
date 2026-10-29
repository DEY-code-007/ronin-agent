const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("island", {
  state: () => ipcRenderer.invoke("state"),
  size: (open) => ipcRenderer.send("size", open),
  media: (cmd) => ipcRenderer.send("media", cmd),
  seen: (id) => ipcRenderer.send("seen", id),
  forget: (id) => ipcRenderer.send("forget", id),
  quit: () => ipcRenderer.send("quit"),
});
