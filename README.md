
Minimal swift script to check the version of the installed [ComfyUI desktop app](https://github.com/Comfy-Org/desktop) against the latest version released on GitHub to see if there is an update available.

## Installation
1. Clone the repository:
```bash
git clone https://github.com/DD-65/comfyui-version-check && cd comfyui-version-check
```

2. Compile to binary:
```bash
swiftc -O -whole-module-optimization comfyui-version-check.swift -o cvc
```

3. Copy to /usr/bin (so that it's included in PATH) & run: (optional)
```bash
sudo mv cvc /usr/local/bin/cvc
cvc
```
