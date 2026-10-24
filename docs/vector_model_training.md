# Four-filter model training and ARM classifier

The network retains the implemented four-filter 3x3 convolution, zero image
borders, ReLU, 2x2 max pooling, and 64-neuron classifier. The FPGA produces
784 packed words; the ARM classifier consumes those words and returns ten
floating-point logits and a digit prediction. This is an INT8 convolution
front end with a floating-point classifier, not a fully integer CNN.

## Training and evaluation

Training uses 55,000 MNIST training images and a disjoint 5,000-image validation
split generated with split seed 2026. Augmentation applies rotations within
10 degrees and translations within 8% of image width/height to training images
only. AdamW uses learning rate 0.001 and weight decay 0.0001, with a cosine
learning-rate schedule. Batch size is 128.

Future training runs select epochs using clean **fixed-feature validation
accuracy**, with the corresponding quantized-feature cross-entropy loss as the
tie-breaker. Each epoch calibrates the integer front end from training-only
images before validation. `--selection-metric float` reproduces the original
training policy. Epoch history, confusion matrices, per-class accuracy, split hash,
seed, checkpoint hash, and runtime version are recorded. Test evaluation is
explicit and is not used for epoch or seed selection. Training refuses to
overwrite an existing checkpoint unless requested.

Two 15-epoch runs used seeds 17 and 29. Seed 17 reached 97.92% validation
accuracy; seed 29 reached 97.64%. Both selected epoch 15 under the original
float-validation policy. Seed 17 was selected before its test evaluation.
A subsequent deployment-validation check measured fixed-feature validation
accuracy of 97.88% for seed 17 and 97.64% for seed 29, confirming the same model.
This confirmation does not reclassify the original experiment as having used
quantized epoch selection. Both the historical selection and the quantized
confirmation are retained. Quantization calibration uses 2,048 training
images excluding validation indices, with the existing 99.9th-percentile
shift-selection policy.

## Measured results

Each row evaluates the same 10,000 MNIST test images with a fixed perturbation.
The noise case uses Gaussian noise with standard deviation 0.05 on a 0..1
image, seed 2026, clipping, and rounding back to uint8. Shift and rotation
use nearest-neighbor sampling and zero fill.

| Input | Baseline fixed-feature accuracy | Candidate fixed-feature accuracy |
| --- | ---: | ---: |
| Clean | 97.03% | 98.37% |
| Shift right by 2 pixels | 83.64% | 97.66% |
| Rotate by +10 degrees | 94.54% | 97.01% |
| Gaussian noise, sigma 0.05 | 96.63% | 97.99% |

Clean floating-point accuracy is 96.97% for the baseline and 98.35% for the
candidate. Fixed-feature results use the integer convolution reference followed
by the floating-point classifier. The baseline was trained with the older
five-epoch procedure and lacks a held-out validation record; this comparison
does not isolate the effects of augmentation, optimizer, or training duration.
Two seeds are recorded, not a statistical confidence claim.

Candidate checkpoint, selection evidence, evaluation/confusion matrices, and
matching front-end parameters are under `generated/candidates/vector_conv4/`.
The baseline checkpoint, default RTL parameters, hardware vectors, bitstreams,
and implementation evidence retain their original identity. To use the
candidate, software must program its matching coefficients through the existing
vector shadow/commit register interface before starting mode 3.

## Reproduce

Install `requirements.txt` into a Python environment. For CPU-only execution,
use the PyTorch CPU wheel index:

```text
python -m pip install -r requirements.txt --index-url https://download.pytorch.org/whl/cpu
python pytorch/train_vector_conv.py --epochs 15 --seed 17 --selection-metric float --device cpu --download --output-dir generated/experiments/vector_conv4_seed17
python pytorch/train_vector_conv.py --epochs 15 --seed 29 --selection-metric float --device cpu --output-dir generated/experiments/vector_conv4_seed29
python pytorch/evaluate_vector_conv.py --checkpoint generated/experiments/vector_conv4_seed17/vector_conv4_cnn.pt --clean-only --output-dir generated/experiments/vector_conv4_seed17/quantized_validation
python pytorch/evaluate_vector_conv.py --checkpoint generated/experiments/vector_conv4_seed29/vector_conv4_cnn.pt --clean-only --output-dir generated/experiments/vector_conv4_seed29/quantized_validation
python scripts/select_vector_candidate.py generated/experiments/vector_conv4_seed17 generated/experiments/vector_conv4_seed29 --output-dir generated/experiments/selected
python pytorch/evaluate_vector_conv.py --checkpoint generated/experiments/selected/vector_conv4_cnn.pt --output-dir generated/experiments/selected/validation
python pytorch/evaluate_vector_conv.py --checkpoint generated/experiments/selected/vector_conv4_cnn.pt --front-manifest generated/experiments/selected/validation/front_manifest.json --split test --output-dir generated/experiments/selected/test
python pytorch/export_vector_classifier.py --checkpoint generated/experiments/selected/vector_conv4_cnn.pt --front-manifest generated/experiments/selected/test/front_manifest.json --output-dir generated/experiments/selected/classifier
```

The default training output is ignored `generated/experiments/`, so exploratory
runs do not replace the hardware checkpoint. Training can use CUDA when a
matching PyTorch installation is present; the recorded experiment used CPU.
For a new experiment, omit `--selection-metric float` to use quantized epoch
selection. Cross-run selection requires each run's `quantized_validation/`
report, checks checkpoint/configuration/split hashes and sample counts, and
rejects test-split metrics.

## C and RTL validation

The exporter folds the positive per-channel dequantization scale into the first
linear layer. Max pooling can therefore operate directly on uint8 features.
Its output order remains channel-major, matching PyTorch flattening after
pooling. Header constants use nine significant digits to preserve float32
weights. Export rejects mismatched convolution parameters and scales.

The C implementation in `software/ultra96/vector_classifier.c` is independent
of Xilinx libraries. With GCC/Clang on PATH or an MSVC developer shell, run:

```text
python scripts/validate_vector_classifier.py
python scripts/validate_vector_classifier.py --model-dir generated/candidates/vector_conv4/classifier
python -m unittest discover -s pytorch -p test_vector_training.py
python scripts/check_vector_model_bundle.py
python -m unittest discover -s scripts -p test_vector_bundle.py
```

Both models pass 27 C/PyTorch cases: eight image feature maps, zero and saturated
features, an asymmetric channel/spatial pattern, and sixteen random feature
maps. Every prediction matches. Maximum absolute logit error is below 0.00006
with MSVC strict floating-point arithmetic. The check permits absolute and
relative tolerance 0.0002 for floating-point reduction differences. The host
test also rejects short and overlong input files. SHA256 checks canonicalize
LF/CRLF for exported text.

The candidate additionally passes every official MNIST test image through the
native-host C classifier: 10,000/10,000 predictions and 100,000/100,000 logits
agree with the PyTorch fixed-feature path within the stated tolerance. The C
accuracy is 98.37%, with maximum absolute logit error below 0.000014 in the
recorded MSVC build. Input features come from the integer convolution reference;
this result does not represent 10,000-image RTL or physical-board execution.
Dataset content hashes, packed-feature hash, C source/header/harness hashes,
and a C confusion matrix are in `c_dataset_evaluation.json`.

```text
python pytorch/validate_vector_dataset.py --output generated/experiments/c-dataset-evaluation.json
```

The batch harness decodes explicit little-endian frames and rejects empty or
truncated input. The full test consumes the existing MNIST dataset and requires
PyTorch plus a native C compiler; temporary features and executables are removed
afterward. CI downloads/caches MNIST and repeats the full test with GCC.

`generated/classifier/bundle.json` and the candidate `bundle.json` bind the
checkpoint, front-end configuration, C exports, golden cases, and source files.
The candidate also binds selection/validation/test reports and full C-dataset
evidence. Verification checks hashes and semantic pairings; it does not silently
refresh locks. After a deliberate model/export/evidence update, regenerate them
with `python scripts/check_vector_model_bundle.py --write`. PyTorch CI also
re-derives weights/configuration from both saved checkpoints using the
exporter's `--check-only` mode. Frozen checkpoint hashes remain unchanged.

The exporter also emits a 44-word configuration memory file. The existing RTL
testbench can load it through AXI-Lite using `+VECTOR_CONFIG_MEM=...`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_vector_candidate_regression.ps1
```

This runs eight candidate images, two consecutive frames per image, with
backpressure and register checks. The test compares 12,544 packed outputs with
the candidate reference. CI builds both C classifiers and validates the
training/evaluation contracts; the Questa lane runs separately on a simulator
host. Board execution remains a separate validation step.
