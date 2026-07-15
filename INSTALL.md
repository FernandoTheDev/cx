# Installing Cx

This guide will help you build and install the Cx compiler from source.

## Prerequisites

To build Cx, you need the following tools installed on your system:

1. **LDC2** (The LLVM D Compiler)
2. **DUB** (The D package manager)
3. **A C Compiler** (GCC or Clang, used by Cx to compile the final output)

### Installing Prerequisites

**Ubuntu / Debian:**

```bash
sudo apt update
sudo apt install ldc dub gcc
```

**Arch Linux:**

```bash
sudo pacman -S ldc dub gcc
```

**Fedora:**

```bash
sudo dnf in ldc dub gcc
```

---

## Quick Installation

The repository includes an automated build script that handles dependency checking, compilation, and installation.

1. **Clone the repository:**

```bash
git clone https://github.com/FernandoTheDev/cx.git
cd cx
```

2. **Run the build script:**

```bash
./build.sh
```

*This script will:*

- Verify that `ldc2` and `dub` are installed.
- Build the compiler in `release` mode.
- Copy the `cx` binary to `~/.local/bin/`.
- Install the standard library to `~/.cx/std/`.

3. **Add `~/.local/bin` to your PATH** (if not already added):

- **Bash:** `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc`
- **Zsh:** `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc`
- **Fish:** `fish_add_path $HOME/.local/bin`

4. **Verify the installation:**

```bash
cx -v
```

*Expected output:* `Cx Compiler - Version (0.x.x)`

---

## Manual Installation (Advanced)

If you prefer not to use the automated script, you can build and install manually:

1. Build the release binary:

```bash
dub build --compiler=ldc2 --build=release
```

2. Move the binary to your local bin directory:

```bash
mkdir -p ~/.local/bin
cp ./cx ~/.local/bin/
```

3. Copy the standard library:

```bash
mkdir -p ~/.cx
cp -r ./std ~/.cx/std
```

---

## Updating Cx

Cx has a built-in update mechanism. To check for and install the latest version, simply run:

```bash
cx update
```

---

## Running Tests

To ensure everything is working correctly on your machine, you can run the compiler's test suite:

```bash
rdmd tests/unit.d
```

*This will compile and execute all examples in the `examples/` directory, verifying both the exit codes and the standard output.*

---

## Uninstalling

To completely remove Cx from your system:

```bash
rm ~/.local/bin/cx
rm -rf ~/.cx
```

*(Don't forget to remove the PATH export from your `~/.bashrc` or `~/.zshrc` if you added it).*
