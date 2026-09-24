# MAINFRAME for Pi

The supported integration is the native [Pi package](pi/SKILL.md), declared by
the root package.json. Preview with `mainframe setup --project . --dry-run`,
apply the reviewed setup with `--yes`, then run `/reload` and
`/mainframe doctor` inside Pi.

Other directories are frozen legacy instruction adapters. They remain for
existing users and recovery, without current support, interception, or runtime
verification claims. Mainframe 10.3 development and tests focus on Pi.
