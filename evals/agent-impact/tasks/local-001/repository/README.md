# Nested configuration fixture

`config_merge.py` merges defaults, project configuration, and user
configuration. Later layers must win without discarding explicit falsy values.
