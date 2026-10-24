"""Focused checks for evaluation isolation, pooling layout, and scale folding."""

import unittest

import torch
from torch.utils.data import DataLoader, TensorDataset

from export_vector_classifier import unpack_words
from train_vector_conv import evaluate, selection_key, split_indices
from vector_conv_model import VectorConvClassifier


class VectorTrainingTests(unittest.TestCase):
    def test_split_has_no_overlap_and_is_reproducible(self):
        training, validation = split_indices(100, 20, 2026)
        self.assertEqual((training, validation), split_indices(100, 20, 2026))
        self.assertFalse(set(training) & set(validation))
        self.assertEqual(set(training) | set(validation), set(range(100)))
        self.assertNotEqual(validation, split_indices(100, 20, 2027)[1])

    def test_invalid_split_rejected(self):
        for size in (0, 100, 101):
            with self.assertRaises(ValueError):
                split_indices(100, size, 0)

    def test_selection_prefers_deployment_accuracy_over_float_accuracy(self):
        first = selection_key({"accuracy": 0.99, "loss": 0.1},
                              {"fixed_feature_accuracy": 0.95, "fixed_feature_loss": 0.2}, "fixed-features")
        second = selection_key({"accuracy": 0.98, "loss": 0.2},
                               {"fixed_feature_accuracy": 0.97, "fixed_feature_loss": 0.3}, "fixed-features")
        self.assertGreater(second, first)
        with self.assertRaises(ValueError):
            selection_key({"accuracy": 0.99, "loss": 0.1}, None, "fixed-features")

    def test_quantized_selection_breaks_ties_on_quantized_loss(self):
        first = selection_key({}, {"fixed_feature_accuracy": 0.97, "fixed_feature_loss": 0.1}, "fixed-features")
        second = selection_key({}, {"fixed_feature_accuracy": 0.97, "fixed_feature_loss": 0.2}, "fixed-features")
        self.assertGreater(first, second)

    def test_evaluation_counts_batches_and_classes(self):
        model = torch.nn.Identity()
        labels = torch.tensor([0, 1, 2, 2, 9])
        logits = torch.eye(10)[labels] * 4
        logits[2] = torch.eye(10)[3] * 4
        report = evaluate(model, DataLoader(TensorDataset(logits, labels), batch_size=2), torch.device("cpu"))
        self.assertEqual(report["samples"], 5)
        self.assertEqual(report["accuracy"], 0.8)
        self.assertEqual(report["confusion_matrix"][2][3], 1)
        self.assertEqual(report["per_class_accuracy"][2], 0.5)

    def test_packed_channel_order(self):
        features = unpack_words([0x04030201] * 784)
        self.assertEqual(features[0, :, 0, 0].tolist(), [1, 2, 3, 4])
        with self.assertRaises(ValueError):
            unpack_words([0] * 783)

    def test_scale_folding_matches_original_classifier(self):
        torch.manual_seed(17)
        model = VectorConvClassifier().eval()
        features = torch.randint(0, 256, (2, 4, 28, 28)).float()
        scales = torch.tensor([0.01, 0.02, 0.03, 0.04])
        expected = model.classify_features(features * scales.reshape(1, 4, 1, 1))
        pooled = model.pool(features).reshape(2, -1)
        weights = model.classifier[0].weight.reshape(64, 4, 196) * scales.reshape(1, 4, 1)
        hidden = torch.relu(torch.nn.functional.linear(pooled, weights.reshape(64, -1), model.classifier[0].bias))
        actual = model.classifier[2](hidden)
        torch.testing.assert_close(actual, expected, rtol=1e-5, atol=1e-5)


if __name__ == "__main__":
    unittest.main()
