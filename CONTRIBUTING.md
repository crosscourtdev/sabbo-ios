# Contributing

Change shared native code here first. Keep public fixtures synthetic and the
project reproducible with `python3 tools/generate_xcode.py`. Run CI before merge.
Do not add production endpoints, real user data, private assets or credentials.
Contributions are made under the repository's MIT license.

Fork pull requests run only on GitHub-hosted machines, with read-only tokens and
no repository secrets. External workflow runs require maintainer approval.
There are no deployment, signing, private-service or self-hosted runner jobs.
Changes to workflows and the generator require careful maintainer review.

Downstream private distributions import an exact reviewed commit and retain
their own profiles, curriculum, artwork and signing workflow. Public CI verifies
the shared code and sample resources, not downstream resource bundles.
