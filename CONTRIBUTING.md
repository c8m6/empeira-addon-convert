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

Contributions are licensed AGPL-3.0-only. Retain attribution and check the origin
and compatibility of any third-party material. No CLA or copyright assignment
is required. For questions use [Empeira Discussions](https://github.com/c8m6/empeira/discussions).
For undisclosed vulnerabilities follow [SECURITY.md](SECURITY.md).
