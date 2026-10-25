"""Guard the benchmark's evidence boundary and sample pairing."""
import unittest
from summarize_vision_benchmark import summarize


def row(path="software", domain="host-functional-model", ticks="100", **extra):
    return dict(model_sha256="a"*64, backend="test", measurement_domain=domain,
                path=path, sample="0", iteration="1", warmup="0", result="0",
                tick_hz="1000000", total_ticks=ticks, prediction="7", **extra)


class BenchmarkTests(unittest.TestCase):
    def test_native_never_claims_speedup(self):
        self.assertEqual(summarize([row(), row("rv32-control", ticks="20")])["speedups"], [])

    def test_paired_board_ratio(self):
        result = summarize([row(domain="board"), row("rv32-control", "board", "20")])
        self.assertEqual(result["speedups"][0]["paired_median_end_to_end_speedup"], 5)

    def test_irq_path_requires_real_board_pair(self):
        self.assertEqual(summarize([row(), row('rv32-irq', ticks='20')])['speedups'], [])
        result = summarize([row(domain='board'), row('rv32-irq', 'board', '25')])
        self.assertEqual(result['speedups'][0]['paired_median_end_to_end_speedup'], 4)

    def test_warmup_removed(self):
        warmup = row(ticks="999"); warmup["warmup"] = "1"
        self.assertEqual(summarize([row(), warmup])["groups"][0]["median_us"], 100)

    def test_duplicate_rejected(self):
        with self.assertRaises(ValueError): summarize([row(), row()])

    def test_wrong_prediction_rejected(self):
        other = row("rv32-control", "board", "20"); other["prediction"] = "2"
        with self.assertRaises(ValueError): summarize([row(domain="board"), other])

    def test_unbound_rejected(self):
        other = row(); other["model_sha256"] = "unbound"
        with self.assertRaises(ValueError): summarize([other])

    def test_failed_run_rejected(self):
        other = row(); other["result"] = "-6"
        with self.assertRaises(ValueError): summarize([other])

    def test_unbalanced_board_samples(self):
        other = row("rv32-control", "board", "20"); other["iteration"] = "2"
        with self.assertRaises(ValueError): summarize([row(domain="board"), other])

    def test_mixed_timer_rejected(self):
        other = row(); other.update(iteration="2", tick_hz="42")
        with self.assertRaises(ValueError): summarize([row(), other])

    def test_zero_board_duration_rejected(self):
        with self.assertRaises(ValueError):
            summarize([row(domain="board"), row("rv32-control", "board", "0")])


if __name__ == "__main__": unittest.main()
