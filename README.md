# Empeira Addon Convert

A small standalone Ruby addon for converting configuration data and generating
Puppet EPP templates with typed parameters and defaults. Licensed AGPL-3.0-only.

## Installation

Requires Ruby 3.2–3.4 on Linux, macOS or WSL2. In an Empeira control repository,
add this entry to the existing `.empeira.yaml`:

```yaml
addons:
  convert:
    git: https://github.com/c8m6/empeira-addon-convert.git
    ref: v1.0.1
```

When a version tag is published, GitHub Actions opens a pull request to update
this `ref` to the latest tag. Because `main` is protected, the change takes effect
after the pull request is merged. Until then, the documented ref may remain `main`
or point to an earlier release.

Run `empeira addons sync`, then `empeira addon convert --help`.
`empeira addons update` refreshes the configured Git ref. Use a commit instead of
`main` when you need reproducible versions. Empeira also installs a missing addon
on its first invocation. This uses Empeira's standalone addon API 1.

After a plain Git checkout, `./bin/convert --help` works directly. No build,
Bundler, Puppet installation or install hooks are required. Ruby must be on PATH.
Paths are relative to the caller's current directory.

## Conversion

| Format | Extension | Read / write |
| --- | --- | --- |
| YAML | `.yaml`, `.yml` | Yes / yes |
| JSON | `.json` | Yes / yes |
| XML | `.xml` | Yes / yes |
| Java Properties | `.properties` | Yes / yes |
| Puppet hash | `.pp` | Yes / yes |

```sh
empeira addon convert run -i input.json -o output.yaml
empeira addon convert run -i input.xml -o output.json
empeira addon convert run -i hiera.yaml -t xml
empeira addon convert run -i input.properties -o output.yaml
empeira addon convert run -i input.yaml -t puppet-hash
empeira addon convert run -i data.txt -f json -t yaml
```

| Option | Meaning |
| --- | --- |
| `-i`, `--input FILE` | Required input file |
| `-o`, `--output FILE` | Output file; omitted means stdout |
| `-f`, `--input-format FORMAT` | Override input filename detection |
| `-t`, `--output-format FORMAT` | Override output filename detection |
| `-h`, `--help` | Show usage |

Use `run` for argument and format autocompletion; the old direct form without
`run` still works. Both `run --help` and `--help` list valid formats and examples.

Format names are `yaml`, `json`, `xml`, `properties`, `puppet-hash`; `yml` and
`pp` also work. Without an output file or format, output is YAML on stdout.
For Puppet hashes, prefer `-t puppet-hash` and stdout. An unknown extension
requires an explicit format. Output files are overwritten after successful
conversion; errors go to stderr with a nonzero exit status.

## EPP templates

```sh
empeira addon convert template -i settings.yaml -o settings.epp
empeira addon convert template -i settings.json  # EPP on stdout
```

All readable formats are supported. The body keeps the input format; `-f`
overrides detection and `-t` is not applicable. For example:

```yaml
server:
  host: localhost
  port: 8080
  enabled: true
  timeout: 30.5
```

Produces parameters equivalent to:

```epp
<%- |
  String $server_host = "localhost",
  Integer $server_port = 8080,
  Boolean $server_enabled = true,
  Float $server_timeout = 30.5
| -%>
```

The generated body uses readable EPP interpolation, for example:
```epp
name: "<%= $hierarchy_0_name %>"
port: <%= $server_port %>
```
Hiera expressions such as `%{facts.os.name}` remain readable in parameter
defaults. This is intentionally a simple starter template, not a complete
escaping or serialization engine: overridden strings containing quotes,
newlines or format-specific special characters may need manual adjustment.
Review and validate generated templates before use. Defaults may contain secrets.

Nested key paths and array indexes become parameter names. Invalid characters
become underscores, names start with a lowercase letter, and collisions get a
numeric suffix. All non-null scalar values become parameters; null stays literal.
Types follow the input parser: YAML/JSON/Puppet preserve strings, integers, floats
and booleans; XML/Properties values are strings. No variable list or mapping file
is needed. Review generated templates before use; defaults may contain secrets.

Comments and original whitespace, quoting and layout are **not preserved**:
the existing serializers produce a normalized body. This is a helper for simple
configuration files, not a general source-rewriting tool. If available, check
the result with `puppet epp validate settings.epp` and render it with
`puppet epp render settings.epp`.

## Data boundaries

- Common data consists of string-keyed mappings, arrays, strings, finite numbers,
  booleans and null. YAML object tags, aliases and implicit date objects are not
  supported; quote dates to treat them as strings. Use one YAML document.
- XML output wraps ordinary Hiera mappings (multiple top-level keys) automatically under a `hiera` root. Keys incompatible with XML element names, including Puppet `::` names, are encoded as `empeira_key_<hex>` and decoded when converted back using this addon. The added root remains visible on XML-to-YAML conversion; it is not stripped automatically.
- XML preserves the root as a mapping key, attributes as `@name`, text alongside
  attributes as `#text`, and repeated elements as arrays. Text stays string data;
  for example `<settings><port>8080</port></settings>` becomes
  `{"settings":{"port":"8080"}}`. XML output needs one root key. Namespaces,
  mixed text/child content, DTDs, null values, empty arrays and nested arrays are
  unsupported. Sibling ordering across different names and scalar types cannot
  round-trip through XML; empty elements become empty strings.
- Properties are flat string mappings. Reading supports comments, escaped
  separators, whitespace separators, continued lines and `\uXXXX` escapes
  (without surrogate pairs). Files use UTF-8; convert legacy encodings first.
  Writing nested data or null fails; other scalar values become strings.
- Puppet input is a bare hash literal with string keys, nested hashes/arrays,
  quoted strings, decimal numbers, booleans and `undef`. Comments and trailing
  commas are accepted. Assignments, expressions, interpolation, classes,
  resources and function calls are unsupported and never executed.
- Conversions can lose format-specific type information. Unsupported structures
  fail with an error; no application-specific mappings are applied.

## Dependencies and development

Uses Ruby libraries `json`, `yaml`/`psych`, `optparse`, `strscan`, and `rexml`
(only for XML). If your Ruby distribution omits one, execution stops clearly:

```text
Error: Missing Ruby dependency: rexml
Install it using:
  gem install rexml
```

Install it yourself in your user's Ruby environment. The addon never installs
anything or requests root access. It introduces no third-party parser gems.

Run `ruby test/convert_test.rb` for eight focused checks, plus the syntax checks
in [CONTRIBUTING.md](CONTRIBUTING.md). CI uses Ruby 3.4 without a test matrix or
Bundler. Empeira API 1 can describe subcommand completion but has no root-option
schema; therefore `run` exposes conversion options for completion. The old root
conversion syntax remains supported.

Questions: [Empeira Discussions](https://github.com/c8m6/empeira/discussions).
Security reports: [SECURITY.md](SECURITY.md).
