# Alfred Workflow Search

This workflow allows you to search for your installed Alfred workflows by their name, all kinds of keywords and hotkeys.

It's super fast and doesn't rely on cache.

You can search for a specific type of keyword with the type surrounded by square brackets (i.e. `[snippet] query`):

- Keyword
- Snippet
- Action (file action or universal action)
- External
- Hotkey

![preview](preview.gif)

## Action on results

- Press `↵` to open the workflow / node in Alfred.
- Press `⌘ ↵` to open the workflow directory in Finder.
- Press `⇧ ↵` to browse the workflow directory in Alfred.
- Press `⌃ ↵` to browse the workflow's cache directory in Alfred.
- Press `fn ↵` to browse the workflow's data directory in Alfred.
- On a workflow matched, press `⇥` to list all of its keywords, press ` ⌘ ` to see its version and description, and access the workflow directory in the result’s action menu.
- On an external trigger, press `⌘ C` to copy its `altr` command.
- On a keyword bound to an external script, you can press `→` to browse the workflow's directory in Alfred, and access the script file in the result's action menu.

## `altr` The command line tool

This workflow comes with a command line tool `altr` that allows you to call any Alfred external trigger in your terminal.

Compared to Alfred’s AppleScript solution, it’s simpler, more straightforward, probably faster, and supports passing variables into the trigger.

### Usage

```bash
altr -w <workflow_id> -t <trigger_id> [-a argument] [-v key=value]…

# you can also pass multiple arguments as an array (if your trigger supports it)
# put `-a` after all other parameters, followed by a `-` and then the arguments
altr -w <workflow_id> -t <trigger_id> [-v key=value]… -a - [multiple arguments…]
```
