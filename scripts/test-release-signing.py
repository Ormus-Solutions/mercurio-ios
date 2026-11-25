#!/usr/bin/env python3
"""release-signing.py's project check, without Xcode or any credentials."""
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "release-signing.py"


def load(team):
    os.environ.pop("MERCURIO_TEAM_ID", None)
    if team is not None:
        os.environ["MERCURIO_TEAM_ID"] = team
    spec = importlib.util.spec_from_file_location("release_signing", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["release_signing"] = module
    spec.loader.exec_module(module)
    return module


def project(module, team_line):
    ids = "\n".join(f"PRODUCT_BUNDLE_IDENTIFIER = {t.bundle_id};" for t in module.TARGETS)
    path = Path(tempfile.mkdtemp()) / "project.pbxproj"
    path.write_text(f"{team_line}\n{ids}\n")
    module.PBXPROJ = path


class CheckProject(unittest.TestCase):
    def test_the_committed_project_names_no_team_and_passes(self):
        module = load("ABCDE12345")
        project(module, 'DEVELOPMENT_TEAM = "";')
        module.check_project()

    def test_a_project_naming_your_team_passes(self):
        module = load("ABCDE12345")
        project(module, "DEVELOPMENT_TEAM = ABCDE12345;")
        module.check_project()

    def test_a_project_naming_another_team_fails(self):
        module = load("ABCDE12345")
        project(module, "DEVELOPMENT_TEAM = ZZZZZ99999;")
        with self.assertRaises(module.SigningError):
            module.check_project()

    def test_no_team_in_the_environment_fails(self):
        module = load(None)
        project(module, 'DEVELOPMENT_TEAM = "";')
        with self.assertRaises(module.SigningError) as raised:
            module.check_project()
        self.assertIn("MERCURIO_TEAM_ID", str(raised.exception))


if __name__ == "__main__":
    sys.exit(unittest.main())
