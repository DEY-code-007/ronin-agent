const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("guard", {
  onState: (fn) => ipcRenderer.on("state", (_e, s) => fn(s)),
  setPin: (pin) => ipcRenderer.invoke("set-pin", pin),
  pin: (pin) => ipcRenderer.invoke("pin", pin),
  input: (what) => ipcRenderer.send("input", what),
  shot: (dataUrl) => ipcRenderer.send("shot", dataUrl),
});
