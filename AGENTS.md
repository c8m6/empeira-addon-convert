# Project conventions

This standalone Empeira API 1 addon converts configuration data and generates
EPP templates. Keep it small: Ruby 3.2–3.4, standard libraries, plain functions,
no Bundler requirement, build step, containers, install hooks or automatic gems.
Do not evaluate input as Ruby or Puppet code. Keep the executable bit on
`bin/convert` and the manifest compatible with Empeira's actual addon API.

Code and documentation use AGPL-3.0-only. Documentation and comments are English.
Support Linux, macOS and WSL2; use portable Ruby file operations. Use synthetic
test data, never production configuration or secrets. Update README examples and
manifest completion when the interface changes. Avoid unrelated features and
new dependencies. Do not create planning or temporary documentation files.

Run `ruby test/convert_test.rb`, syntax checks and `git diff --check` before
committing. Validate generated EPP with Puppet/OpenVox when available. Report
actual checks and unavailable tools honestly. Use focused Conventional Commits
and follow the user's branch and push instructions.
