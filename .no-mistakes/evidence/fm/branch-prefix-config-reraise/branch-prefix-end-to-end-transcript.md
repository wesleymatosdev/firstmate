# branch-prefix config — end-to-end captain flow (real CLI run)

Commands run against this change's `bin/` scripts with a fixture `FM_HOME`
(registry excerpt below). This is the flow a captain experiences: register a
standing per-project prefix, resolve it at intake, generate the ship brief.

## Registry (`data/projects.md` fixture)

```
- acme-widget [direct-PR branch=fix/] - third-party repo, must not read as firstmate-authored (added 2026-09-23)
- firstmate-core [direct-PR] - firstmate's own repo, no branch annotation (added 2026-09-23)
```

## 1. Intake resolves the standing per-project prefix

```
$ FM_HOME=$HOME bin/fm-project-mode.sh --branch-prefix acme-widget
fix/
$ FM_HOME=$HOME bin/fm-project-mode.sh --branch-prefix firstmate-core
fm/
```

A project with no `branch=` annotation keeps the legacy `fm/` default; the
annotation is invisible to the default `<mode> <yolo>` output (existing
callers unaffected).

## 2. Brief generation uses the resolved prefix

```
$ FM_HOME=$HOME bin/fm-brief.sh 4273 acme-widget --mode direct-PR --branch-prefix 'fix/'
scaffolded: .../data/4273/brief.md (ship, mode=direct-PR; replace {TASK} and {FIRSTMATE_SPEC})
$ FM_HOME=$HOME bin/fm-brief.sh 512 firstmate-core --mode direct-PR
scaffolded: .../data/512/brief.md (ship, mode=direct-PR; replace {TASK} and {FIRSTMATE_SPEC})
```

## 3. What the worker actually receives

Third-party project (`branch=fix/`) — brief for task 4273:

```
1. First action: create your branch: `git checkout -b fix/4273 --`
1. Never push to the default branch (push only your `fix/4273` branch). Never merge a PR.
Ship branch: fix/4273
```

Zero occurrences of `fm/4273` in the whole brief — no firstmate branding
reaches the third-party repo.

Firstmate's own repo (no annotation) — brief for task 512, byte-identical to
pre-change behavior:

```
1. First action: create your branch: `git checkout -b fm/512 --`
1. Never push to the default branch (push only your `fm/512` branch). Never merge a PR.
Ship branch: fm/512
```

## Automated suites backing this flow

All pass under tasks-axi 0.2.6 (spawn-dispatch leg requires it):
`tests/fm-brief.test.sh`, `tests/fm-task-delivery.test.sh` (incl. the
brief/spawn branch-mismatch refusal and `fm-project-mode.sh --branch-prefix`
resolution tests), `tests/fm-control-relaunch.test.sh`,
`tests/fm-bearings-snapshot.test.sh`, `tests/fm-review-diff.test.sh`.
