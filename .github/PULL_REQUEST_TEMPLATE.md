## Description

Brief description of the changes in this PR.

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring

## Which Libraries Are Affected?

- [ ] common.sh
- [ ] pure-string.sh
- [ ] pure-array.sh
- [ ] pure-util.sh
- [ ] pure-file.sh
- [ ] json.sh
- [ ] Other: ___

## Checklist

- [ ] My code follows the project's style guidelines (pure bash, no external dependencies)
- [ ] I have added tests that prove my fix/feature works
- [ ] All existing tests pass (`bats tests/`)
- [ ] I have updated documentation if needed
- [ ] Functions are exported with `export -f`
- [ ] Function names use snake_case
- [ ] New functions have usage comments

## Testing

Describe how you tested these changes:

```bash
# How to test this PR
bats tests/unit/test_<library>.bats
```

## Related Issues

Fixes #(issue number)

## Additional Notes

Any additional information that reviewers should know.
