# Like uses_dependency.py but with correct types, so ty exits 0 when it can
# resolve the workspace import.  Regression test for
# https://github.com/aspect-build/rules_lint/issues/728
from typing import TYPE_CHECKING

from dependency import greet

if TYPE_CHECKING:
    from stub import stub_greet

    stub_message: str = stub_greet("World")


def main() -> None:
    message: str = greet("World")
    print(message)
