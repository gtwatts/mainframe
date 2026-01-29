# Changelog

All notable changes to the MAINFRAME Bash Language Support extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-01-28

### Added

- **VS Code Extension Client**
  - Automatic MAINFRAME installation detection
  - Status bar integration with click-to-toggle
  - Configuration UI for all settings
  - Auto-activation for `.sh` and `.bash` files

- **Language Server Protocol Support**
  - Smart autocompletion for 2,000+ MAINFRAME functions
  - Rich hover documentation with markdown formatting
  - Signature help with parameter hints
  - Document symbols (outline view)
  - Go-to-definition for library files

- **Commands**
  - `MAINFRAME: Restart LSP Server`
  - `MAINFRAME: Toggle MAINFRAME LSP`
  - `MAINFRAME: Show FUNCTIONS.json Path`
  - `MAINFRAME: Open Settings`

- **Configuration Options**
  - `mainframe.enable` - Enable/disable LSP
  - `mainframe.functionsPath` - Custom FUNCTIONS.json path
  - `mainframe.showHints` - Toggle inline parameter hints

- **Auto-detection Features**
  - Detects `$MAINFRAME_ROOT` environment variable
  - Falls back to `~/.mainframe` default location
  - Validates FUNCTIONS.json exists before starting server

- **Developer Experience**
  - ESLint configuration for code quality
  - TypeScript strict mode enabled
  - Vitest integration for testing
  - VSCE packaging support

### Fixed

- Status bar updates correctly on configuration changes
- Server restarts cleanly when settings change
- Proper error handling for missing MAINFRAME installations

### Documentation

- Comprehensive README with installation instructions
- Troubleshooting guide
- Development setup guide
- VS Code marketplace preparation

## [Unreleased]

### Planned

- **Enhanced Diagnostics**
  - Warn about undefined MAINFRAME functions
  - Suggest similar function names for typos
  - Validate function parameter counts

- **Code Actions**
  - Quick fix to add `source` statement
  - Import specific library files
  - Generate function stubs

- **Workspace Features**
  - Search all MAINFRAME functions across workspace
  - Find references to MAINFRAME functions
  - Rename refactoring support

- **Performance**
  - Incremental function parsing
  - Caching for large codebases
  - Lazy loading of library documentation

- **Testing**
  - End-to-end LSP tests
  - Integration tests with VS Code API
  - Performance benchmarks

---

[1.0.0]: https://github.com/gtwatts/mainframe/releases/tag/lsp-v1.0.0
