# runtime/tests/vendor

This directory holds test-harness dependencies vendored as git submodules.

## bats-core

`bats-core` is the bash test framework used by `runtime/tests/`.

To initialise it after cloning:

    git submodule add https://github.com/bats-core/bats-core.git runtime/tests/vendor/bats-core
    git submodule update --init --recursive

Once added, `make -C runtime test` will automatically use the vendored copy at
`runtime/tests/vendor/bats-core/bin/bats` in preference to any system-installed `bats`.

If you are working without the submodule (e.g. a shallow clone for CI inspection),
install bats-core system-wide and `make test` will fall back to the PATH copy.
