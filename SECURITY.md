# Security policy

Use [GitHub private vulnerability reporting](https://github.com/c8m6/empeira-addon-convert/security/advisories/new)
if enabled. Otherwise ask for a private contact through
[Empeira Discussions](https://github.com/c8m6/empeira/discussions), without posting
vulnerability details. Do not disclose exploits in public issues or pull requests.
No email contact or response-time guarantee is provided.

Include the affected commit, Ruby version and a small reproduction with synthetic
data. Never attach production configuration or secrets. There is no guaranteed
backport policy; check the current `main` revision when reporting.

The addon runs with the invoking user's file permissions. Input must remain data:
YAML object deserialization, XML DTDs and execution of Ruby or Puppet input are
outside its contract. Generated templates contain the input defaults, which may
be sensitive; review them before committing or sharing. Large, deeply nested or
otherwise hostile files are not a supported resource-isolation boundary.
