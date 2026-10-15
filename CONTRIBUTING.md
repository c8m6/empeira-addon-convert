# Contributing

Keep changes focused and follow [AGENTS.md](AGENTS.md). Use Conventional Commits.
Use synthetic configuration in reports and tests. Documentation is English.

Run the small test script and syntax checks without Bundler:

```sh
ruby test/convert_test.rb
ruby -c bin/convert
ruby -c lib/convert.rb
ruby -c lib/puppet_hash.rb
git diff --check
```

Check generated templates with `puppet epp validate FILE.epp` when Puppet or
OpenVox is available. State which checks actually ran. Runtime dependencies are
Ruby libraries; do not add automatic installation, build steps or infrastructure.
The Linux matrix installs Ubuntu's signed `puppet-agent` package to execute the
existing validate/render/parse round trips for every output format on each Ruby.
Puppet uses its distribution Ruby independently from the addon's selected Ruby.
On hosted macOS that optional tool is absent; its tests report the EPP check as
unavailable while still running all standalone behavior and Core acceptance.

Contributions are licensed AGPL-3.0-only. Retain attribution and check the origin
and compatibility of any third-party material. No CLA or copyright assignment
is required. For questions use [Empeira Discussions](https://github.com/c8m6/empeira/discussions).
For undisclosed vulnerabilities follow [SECURITY.md](SECURITY.md).

## Ruby compatibility

Ruby 3.1 is the minimum; support Ruby 3.1, 3.2, 3.3, 3.4 and 4.0 without
changing the Empeira API 1 interface. Regular CI runs the complete standalone
behavioral suite on Ubuntu 24.04 and native macOS 15 for every version, including
a required Ruby 4.0 job. Require optional libraries explicitly; never install
dependencies automatically. Use the same Ruby on PATH for Core and the addon.

Core integration is tested by the shared acceptance gate in the reviewed Empeira
checkout. With this checkout under `/path/to/checkouts/empeira-addon-convert`, run
from the Core checkout:

```sh
EMPEIRA_OFFICIAL_ADDON_ROOT=/path/to/checkouts EMPEIRA_OFFICIAL_ADDONS=convert \
  bundle exec rspec spec/acceptance/official_addons.rb
```

This gate installs the real addon through Core's Git/cache/manifest path and
exercises configuration, revision updates, terminal I/O, arguments and errors in
synthetic repositories. Missing sources fail explicitly. CI pins the Core revision;
update it deliberately when the contract changes. Core owns its RSpec, RuboCop and
dual lockfile audit dependencies; this standalone addon still needs no Bundler.
Native Windows is unsupported. WSL2 and real engine capabilities need separate
real-host validation; Linux/macOS unit results do not establish those results.
