"""Regression checks for accidental artifact mixing and test-set selection."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from check_vector_model_bundle import ROOT, check_bundle, digest
from select_vector_candidate import load_candidate


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle_path = self.root / "bundle.json"
        self.bundle = json.loads((ROOT / "generated/classifier/bundle.json").read_text())
        for entry in self.bundle["files"].values():
            destination = self.root / entry["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / entry["path"], destination)
        self.save_bundle()

    def save_bundle(self):
        self.bundle_path.write_text(json.dumps(self.bundle), encoding="utf-8")

    def test_complete_pair_passes(self):
        check_bundle(self.bundle_path, self.root)

    def test_changed_weight_header_rejected(self):
        path = self.root / self.bundle["files"]["classifier_weights"]["path"]
        path.write_bytes(path.read_bytes() + b"\n/* changed */\n")
        with self.assertRaisesRegex(ValueError, "integrity"):
            check_bundle(self.bundle_path, self.root)

    def test_rehashed_wrong_checkpoint_still_rejected(self):
        entry = self.bundle["files"]["checkpoint"]
        path = self.root / entry["path"]
        path.write_bytes(b"different checkpoint")
        entry["sha256"] = digest(path)
        self.save_bundle()
        with self.assertRaisesRegex(ValueError, "pairing"):
            check_bundle(self.bundle_path, self.root)

    def test_repository_escape_rejected(self):
        self.bundle["files"]["checkpoint"]["path"] = "../outside.pt"
        self.save_bundle()
        with self.assertRaisesRegex(ValueError, "escapes"):
            check_bundle(self.bundle_path, self.root)

    def test_crlf_checkout_keeps_text_identity(self):
        entry = self.bundle["files"]["front_config_mem"]
        path = self.root / entry["path"]
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        check_bundle(self.bundle_path, self.root)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.run = Path(self.temporary.name)
        checkpoint = self.run / "vector_conv4_cnn.pt"
        checkpoint.write_bytes(b"checkpoint fixture")
        self.checkpoint_hash = digest(checkpoint)
        (self.run / "metrics_vector_conv4.json").write_text(json.dumps({
            "validation": {"accuracy": 0.99, "loss": 0.01}, "validation_samples": 5,
            "validation_indices_sha256": "fixed split", "checkpoint_sha256": self.checkpoint_hash,
        }))
        evaluation = self.run / "quantized_validation"
        evaluation.mkdir()
        front = evaluation / "front_manifest.json"
        front.write_text("{}\n")
        self.report = {"split": "validation", "checkpoint_sha256": self.checkpoint_hash,
                       "front_manifest_sha256": digest(front), "validation_indices_sha256": "fixed split",
                       "results": {"clean": {"samples": 5, "fixed_feature_accuracy": 0.8, "fixed_feature_loss": 0.4}}}
        self.report_path = evaluation / "evaluation.json"
        self.save_report()

    def save_report(self):
        self.report_path.write_text(json.dumps(self.report))

    def test_loader_uses_quantized_metric(self):
        candidate = load_candidate(self.run)
        self.assertEqual(candidate[:2], (0.8, -0.4))

    def test_test_set_selection_rejected(self):
        self.report["split"] = "test"
        self.save_report()
        with self.assertRaisesRegex(ValueError, "test-set"):
            load_candidate(self.run)

    def test_validation_split_mismatch_rejected(self):
        self.report["validation_indices_sha256"] = "different split"
        self.save_report()
        with self.assertRaisesRegex(ValueError, "different validation split"):
            load_candidate(self.run)

    def test_wrong_checkpoint_report_rejected(self):
        self.report["checkpoint_sha256"] = "wrong"
        self.save_report()
        with self.assertRaisesRegex(ValueError, "different checkpoint"):
            load_candidate(self.run)


if __name__ == "__main__":
    unittest.main()
