"""Select the newest advertised model in one family for a new assignment."""

import argparse
import re


def latest_model(family, available):
    pattern = re.compile(r"gpt-(\d+(?:\.\d+)*)-" + re.escape(family))
    versions = []
    for model in available:
        match = pattern.fullmatch(model)
        if match:
            version = tuple(int(part) for part in match[1].split("."))
            versions.append((version, model))
    return max(versions)[1] if versions else None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("family", choices=("astra", "sol"))
    parser.add_argument("available", nargs="+", help="Exact model IDs offered by this session")
    args = parser.parse_args()
    selected = latest_model(args.family, args.available)
    if selected is None:
        parser.exit(1, f"No versioned {args.family} model in the supplied inventory.\n")
    print(selected)
