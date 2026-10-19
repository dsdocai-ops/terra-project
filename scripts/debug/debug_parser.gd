class_name DebugParser
extends RefCounted
## Tokenizes a debug console command line: splits on whitespace and honors
## double-quoted arguments ("spawn grub 2 elite \"drain\"" keeps the affix's
## spaces together). A backslash before a double quote inside quotes escapes
## it. Owned by debug-tools (W2-B4).
## Sync: none — pure string handling.

## Splits `line` into tokens. Quoted runs keep interior spaces; an
## unterminated quote keeps the partial token. Returns an empty array for a
## blank line.
static func tokenize(line: String) -> PackedStringArray:
	var tokens: PackedStringArray = []
	var current := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var ch: String = line[i]
		if in_quotes:
			if ch == "\"":
				in_quotes = false
			elif ch == "\\" and i + 1 < line.length() and line[i + 1] == "\"":
				current += "\""
				i += 1
			else:
				current += ch
		elif ch == "\"":
			in_quotes = true
		elif ch == " " or ch == "\t":
			if not current.is_empty():
				tokens.append(current)
				current = ""
		else:
			current += ch
		i += 1
	if not current.is_empty():
		tokens.append(current)
	return tokens
