"""Imports from the standard library, third-party and first-party packages, correctly sorted."""

import json

import requests

from first_party_lib import helper


def main() -> None:
    """Use each import."""
    print(json.dumps({"helper": helper.helper(), "session": str(requests.Session())}))
