"""Extract portable, artifact-bound implementation evidence from an RV32 SoC build."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, default=ROOT)
    parser.add_argument('--source-ref', required=True, help='Git revision actually used for implementation')
    parser.add_argument('--output', type=Path, default=ROOT / 'generated/experiments/vivado-implementation.json')
    args = parser.parse_args()
    build = args.build_root.resolve()
    reports = build / 'hardware/reports/ultra96_v2/rv32_soc/impl'
    impl = build / 'vivado/u96v2_rv32_soc_vivado/u96v2_rv32_soc.runs/impl_1'
    bit, xsa = impl / 'u96v2rv32_wrapper.bit', build / 'vivado/ultra96_v2_rv32_ai_vision_soc.xsa'
    timing = (reports / 'timing_summary.rpt').read_text()
    row = re.search(r'^\s*WNS\(ns\).*\n[^\n]*\n([^\n]+)', timing, re.M)
    if not row or len(values := row[1].split()) != 12:
        raise RuntimeError('Unknown timing-summary format')
    keys = ('setup_wns_ns', 'setup_tns_ns', 'setup_failing', 'setup_endpoints',
            'hold_whs_ns', 'hold_ths_ns', 'hold_failing', 'hold_endpoints',
            'pulse_wpws_ns', 'pulse_tpws_ns', 'pulse_failing', 'pulse_endpoints')
    metrics = {key: float(value) if index % 4 < 2 else int(value)
               for index, (key, value) in enumerate(zip(keys, values))}
    if any(metrics[k] != 0 for k in ('setup_failing', 'hold_failing', 'pulse_failing')):
        raise RuntimeError('Implementation has failing timing endpoints')
    skew_path = impl / 'u96v2rv32_wrapper_bus_skew_routed.rpt'
    slacks = [float(v) for v in re.findall(r'^\s+(?:Slow|Fast)\s+\S+\s+\S+\s+(\S+)\s*$',
                                          skew_path.read_text(), re.M)]
    if not slacks or min(slacks) < 0:
        raise RuntimeError('Missing/failing bus-skew checks')
    drc = (reports / 'drc.rpt').read_text()
    findings = re.findall(r'^\|\s*([A-Z]+-\d+)\s*\|\s*([^|]+)\|[^|]+\|\s*(\d+)\s*\|', drc, re.M)
    count = re.search(r'Checks found:\s*(\d+)', drc)
    if not count or int(count[1]) != sum(int(n) for _, _, n in findings):
        raise RuntimeError('Incomplete DRC summary')
    if any(severity.strip() != 'Warning' for _, severity, _ in findings):
        raise RuntimeError('DRC has error/critical findings')
    cdc = re.findall(r'^(CDC-\d+)\s+(Info|Warning|Critical(?:\s+Warning)?)\s+(\d+)\s',
                     (reports / 'cdc.rpt').read_text(), re.M)
    if not cdc or any(severity != 'Info' for _, severity, _ in cdc):
        raise RuntimeError('Missing CDC summary or noninformational findings')
    methodology = re.search(r'Checks found:\s*(\d+)', (reports / 'methodology.rpt').read_text())
    if not methodology or int(methodology[1]):
        raise RuntimeError('Missing/nonempty methodology summary')
    utilization = (reports / 'utilization.rpt').read_text()
    resources = {}
    for label in ('CLB LUTs', 'CLB Registers', 'Block RAM Tile', 'DSPs'):
        match = re.search(r'^\|\s*' + label + r'\s*\|\s*(\S+)\s*\|[^|]*\|[^|]*\|\s*(\S+)\s*\|\s*(\S+)\s*\|', utilization, re.M)
        if not match:
            raise RuntimeError('Resource row missing: ' + label)
        resources[label] = dict(used=float(match[1]), available=int(match[2]), percent=float(match[3]))
    power = (reports / 'power.rpt').read_text()
    watts = float(re.search(r'Total On-Chip Power \(W\)\s*\|\s*([\d.]+)', power)[1])
    bit_hash = hashlib.sha256(bit.read_bytes()).hexdigest()
    with zipfile.ZipFile(xsa) as archive:
        members = [n for n in archive.namelist() if n.endswith('.bit')]
        if len(members) != 1 or hashlib.sha256(archive.read(members[0])).hexdigest() != bit_hash:
            raise RuntimeError('XSA embedded bitstream does not match implementation')
    commit = subprocess.check_output(['git', 'rev-parse', args.source_ref], cwd=ROOT, text=True).strip()
    files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', commit], cwd=ROOT, text=True).splitlines()
    hashes = {}
    for name in files:
        if (name.startswith('rtl/') and name.endswith('.sv')) or (name.startswith('vivado/constraints/') and name.endswith('.xdc')):
            reference = subprocess.check_output(['git', 'show', f'{commit}:{name}'], cwd=ROOT).replace(b'\r\n', b'\n')
            actual = (build / name).read_bytes().replace(b'\r\n', b'\n')
            if reference != actual:
                raise RuntimeError('Build mirror source differs from claimed commit: ' + name)
            hashes[name] = hashlib.sha256(reference).hexdigest()
    result = dict(tool='Vivado 2025.2', source_commit=commit, target='xczu3eg-sbva484-1-i',
        clocks_mhz=dict(control=100.0, stream=150.015), timing=metrics,
        bus_skew=dict(constraints=len(slacks), minimum_slack_ns=min(slacks)),
        cdc={rule: int(count) for rule, _, count in cdc}, methodology_findings=0,
        drc_warnings={rule: int(count) for rule, _, count in findings}, resources=resources,
        power=dict(estimated_watts=watts, confidence='Medium', simulation_activity=False, measured=False),
        artifacts_sha256={bit.name: bit_hash, xsa.name: hashlib.sha256(xsa.read_bytes()).hexdigest()},
        xsa_embedded_bit_matches=True, physical_board_execution=False, source_sha256_lf=hashes,
        report_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(reports.glob('*.rpt'))})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: timing/skew/CDC/DRC, source revision and embedded bitstream verified; portable evidence recorded')


if __name__ == '__main__':
    main()
