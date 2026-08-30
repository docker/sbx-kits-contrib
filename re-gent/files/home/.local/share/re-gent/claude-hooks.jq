# Mirror of re_gent's installClaudeHook merge, in jq.
#
# Upstream equivalents, for re-checking when RGT_VERSION is bumped:
#   capture.IsRegentCommand  -> is_rgt_cmd
#   normalizeHookGroups      -> norm_groups
#   normalizeHookArray       -> norm_entries
#   filterRegentHookCommands -> clean_group / keep_group
#   hookGroup                -> new_group

# Does this command string belong to re_gent? Mirrors IsRegentCommand: skip
# leading VAR=value assignments, then match the basename of the first real
# field against rgt/regent, or a `go run ... cmd/rgt` invocation.
#
# Matching upstream's breadth matters: a narrower rule (e.g. plain
# `startswith("rgt ")`) misses `/usr/local/bin/rgt message-hook assistant`,
# which `rgt init` itself can write, and the entry would then survive the
# filter and get a duplicate appended on every container start.
def is_rgt_cmd:
  ((. | strings) // "") as $c
  # \\s+, not [ \t]+: upstream uses strings.Fields, which splits on all
  # whitespace, so a command carrying a newline must still be recognized.
  | ($c | [splits("\\s+")] | map(select(length > 0))) as $fields
  | ($fields
     | until(length == 0
             or ((.[0] | contains("=")) | not)
             or (.[0] | startswith("="));
             .[1:])) as $f
  | if ($f | length) == 0 then false
    else
      (($f[0] | split("/") | last | ltrimstr("./")) as $first
       | $first == "rgt"
         or $first == "regent"
         or (($f | length) >= 3
             and $f[0] == "go"
             and $f[1] == "run"
             and ($f[2] | contains("cmd/rgt"))))
    end;

# A string becomes a single command group; a lone object becomes a
# one-element list; an array passes through.
def norm_groups:
  if   type == "array"  then .
  elif type == "string" then [{matcher: "", hooks: [{type: "command", command: .}]}]
  elif type == "object" then [.]
  elif . == null        then []
  else [.] end;

# A group's "hooks" may be a bare object rather than an array. null means the
# key is absent, which the caller must distinguish from an empty list.
def norm_entries:
  if   type == "array"  then .
  elif . == null        then null
  elif type == "object" then [.]
  else [.] end;

# Drop rgt-owned entries from each group. A group with no "hooks" key is
# passed through untouched, exactly as upstream does.
def clean_group:
  if type != "object" then .
  else
    (.hooks | norm_entries) as $entries
    | if $entries == null then .
      else .hooks = ($entries | map(select(
             # Only objects can be rgt entries. Non-objects are passed
             # through, as upstream does: `.command?` on a string yields
             # `empty`, which would make `select` drop the entry entirely and
             # silently delete it from the user's real settings.json.
             if type == "object" then ((.command? | is_rgt_cmd) | not) else true end
           )))
      end
  end;

# A group that *had* a hooks array and is now empty is dropped; a group that
# never had one is kept.
def keep_group:
  (type != "object") or ((.hooks | type) != "array") or ((.hooks | length) > 0);

# hookGroup: upstream sets matcher to the empty string. Omitting it would make
# settings.json flip between two shapes if the user ever also runs `rgt init`.
def new_group($cmd):
  {matcher: "", hooks: [{type: "command", command: $cmd}]};

def merge_hook($event; $cmd):
  # Bind the surviving groups BEFORE reassigning .hooks: inside a
  # `(.hooks // {}) | ...` pipe the identity rebinds to the hooks object, so
  # an inner `.hooks[$event]` would read the wrong level and silently drop
  # the user's existing hooks for this event.
  (((.hooks // {})[$event]) | norm_groups | map(clean_group) | map(select(keep_group))) as $kept
  | .hooks = ((.hooks // {}) | .[$event] = ($kept + [new_group($cmd)]));

# removeRegentHookCommands: strip rgt entries, delete the event if nothing left.
def remove_hook($event):
  (((.hooks // {})[$event]) | norm_groups | map(clean_group) | map(select(keep_group))) as $kept
  | .hooks = ((.hooks // {}) | .[$event] = $kept)
  | if ($kept | length) == 0 then (.hooks |= del(.[$event])) else . end;

merge_hook("UserPromptSubmit"; "rgt message-hook user")
| merge_hook("Stop"; "rgt message-hook assistant")
| merge_hook("PostToolBatch"; "rgt tool-batch-hook")
| remove_hook("PostToolUse")
