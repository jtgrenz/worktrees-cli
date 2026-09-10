# worktrees

A small Ruby CLI for browsing, creating, styling, and removing Git worktrees.

## Requirements

- Ruby 3.2+
- Git
- [GitHub CLI](https://cli.github.com/), authenticated for the repository
- `GUI_EDITOR` set to the command that opens a directory

The CLI otherwise uses only Ruby's standard library.

```sh
export GUI_EDITOR="code"
# or
export GUI_EDITOR="cursor --reuse-window"
```

Run `./worktrees` from this checkout, or symlink it somewhere on your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/worktrees" ~/.local/bin/worktrees
```

## Usage

```sh
worktrees
worktrees --prune
worktrees style [PATH]
```

`worktrees` lists every registered worktree. Select one to open it with
`$GUI_EDITOR`, or select **New worktree** to create one beside the primary
checkout from `origin/main`.

`worktrees --prune` shows every secondary worktree with its age and status,
then removes the selected worktree after confirmation. Merged status checks
both Git ancestry and merged GitHub pull requests through `gh`.

`worktrees style [PATH]` gives a linked worktree a distinct title bar in
VS Code-compatible editors. The primary checkout opts in and supplies the
repository color through `.vscode/settings.json`:

```json
{
  "peacock.color": "#123456"
}
```

The command preserves existing valid settings, adds an orange worktree cue,
and sets the window title to the active branch followed by `WT`. It is a no-op
for the primary checkout or when the primary Peacock color is absent. Other
editors still open through `$GUI_EDITOR`; they simply ignore these settings.

Creation and merged-status detection currently assume `main`, `origin/main`,
an `origin` remote, and GitHub hosting. Set `NO_COLOR` to disable terminal
colors.

## Development

```sh
ruby -Itest test/worktrees_test.rb
```
