# LogPopup

A macOS command-line utility that executes commands and displays their output in a popup window while simultaneously showing it in the terminal.

## Features

- Run any command with a GUI popup showing real-time output
- Combines stdout and stderr in the popup
- Automatically closes on success, configurable behavior on failure
- Monospaced font for proper formatting
- Auto-scroll with manual scroll override
- Signal handling (Ctrl+C support)

## Usage

```bash
logpopup [--keep-on-fail] [--help] [--version] <command> [args...]
```

### Options

- `--keep-on-fail`: Keep window open if command fails (default: closes after 5 seconds)
- `--help`: Show help message and exit
- `--version`: Show version and exit

### Examples

```bash
# Run a build command with popup output
logpopup make build

# Use your own shell
logpopup bash -c 'my_alias'
logpopup fish -c 'for i in (seq 1 10); echo "Line $i"; end'

# Keep window open on failure
logpopup --keep-on-fail npm test

# Run with arguments
logpopup git log --oneline -10
```

## Building

```bash
./build.sh
```

## Requirements

- macOS
- Swift compiler
