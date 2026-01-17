# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.1.x   | :white_check_mark: |
| 2.0.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in MAINFRAME, please report it responsibly.

### How to Report

1. **Do NOT open a public issue** for security vulnerabilities
2. Email security concerns to the repository owner
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- Acknowledgment within 48 hours
- Status update within 7 days
- Fix timeline depends on severity

### Security Considerations for MAINFRAME

Since MAINFRAME provides bash utility functions, security considerations include:

- **Input Validation**: Functions in `validation.sh` help sanitize user input
- **Path Safety**: `path_is_safe()` prevents directory traversal attacks
- **Command Injection**: `sanitize_shell_arg()` escapes dangerous characters
- **No External Dependencies**: Reduces supply chain attack surface

### Safe Usage Guidelines

```bash
# Always validate untrusted input
validate_path_safe "$user_input" "/allowed/base" || exit 1

# Sanitize before using in commands
safe_arg=$(sanitize_shell_arg "$user_input")

# Use safe path operations
path_is_safe "/base" "$path" && cd "$path"
```

## Security Best Practices

When using MAINFRAME in production:

1. **Validate all external input** using validation.sh functions
2. **Use path safety functions** for file operations
3. **Sanitize shell arguments** before command execution
4. **Keep MAINFRAME updated** to get security fixes
5. **Review scripts** that use MAINFRAME before deployment
