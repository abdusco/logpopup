# LogPopup

A mini macOS command-line utility that executes commands and shows their output in a popup window.

<video src="https://github.com/user-attachments/assets/46a9a068-fbb4-479d-abf7-35acd90e024b" controls width="600"></video>

## Features

- Run any command with a GUI popup showing real-time output
- Combines `stdout` and `stderr` in the popup
- Automatically closes on success, optionally keeps open on failure
- Auto-scroll to the end
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
