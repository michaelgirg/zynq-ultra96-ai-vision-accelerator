"""Bounded safety on real mailbox RTL with mechanically lowered return syntax."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yosys')
    parser.add_argument('--depth', type=int, default=32)
    parser.add_argument('--output', type=Path, default=ROOT / 'generated/experiments/mailbox-formal')
    args = parser.parse_args()
    if not 16 <= args.depth <= 64:
        raise SystemExit('depth must be 16..64')
    exe = args.yosys or shutil.which('yosys') or shutil.which('yowasp-yosys')
    if not exe:
        raise SystemExit('Yosys required')
    output = args.output.resolve()
    output.relative_to(ROOT)  # All generated derivatives stay inside the repo.
    output.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'rtl/riscv/soc/rv32_job_mailbox.sv'
    props = ROOT / 'verif/formal/rv32_mailbox_properties.svh'
    text = source.read_text()
    replacements = {
        "return (&value) ? value : value + 1'b1;": "increment_sat = (&value) ? value : value + 1'b1;",
        "return address[1:0] == 2'b00;": "address_aligned = address[1:0] == 2'b00;",
        'endmodule': props.read_text() + '\nendmodule',
    }
    for old, new in replacements.items():
        if text.count(old) != 1:
            raise SystemExit('RTL normalization anchor changed; review formal instrumentation')
        text = text.replace(old, new)
    env = os.environ.copy()
    wasm = 'yowasp' in Path(exe).name
    if wasm:
        env.update(YOWASP_MOUNT='/repo=.', YOWASP_CACHE_DIR=str(ROOT / '.venv/yowasp-cache'))
    prefix = '/repo/' if wasm else ''
    help_text = subprocess.check_output([exe, '-Q', '-T', '-p', 'help chformal'],
                                        cwd=ROOT, env=env, text=True)
    lower = 'async2sync; chformal -lower; ' if '-lower' in help_text else ''

    def check(name: str, rtl: str, negative: bool = False) -> None:
        path = output / (name + '.sv')
        path.write_text(rtl)
        command = (f'read_verilog -formal -D SYNTHESIS -sv {prefix}{path.relative_to(ROOT).as_posix()}; '
                   'prep -top rv32_job_mailbox; flatten; ' + lower +
                   f'sat -verify -prove-asserts -set-assumes -seq {args.depth}')
        result = subprocess.run([exe, '-p', command], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=300)
        log = result.stdout + result.stderr
        (output / (name + '.log')).write_text(log)
        if negative:
            if result.returncode == 0 or 'proof did fail' not in log:
                raise SystemExit(f'Mutation not detected: {name}')
        elif result.returncode or 'SUCCESS!' not in log:
            raise SystemExit(f'Mailbox proof failed: {name}; inspect generated log')

    check('mailbox', text)
    target = 'irq_status <= irq_status & ~wdata[2:0];'
    if text.count(target) != 1:
        raise SystemExit('W1C mutation anchor changed')
    check('w1c_mutant', text.replace(target, 'irq_status <= irq_status;'), True)
    target = "first_fault_kind == 0"
    if source.read_text().count(target) != 2:
        raise SystemExit('First-fault mutation anchor changed')
    check('first_fault_mutant', text.replace(target, "1'b1", 2), True)
    version = subprocess.check_output([exe, '-V'], cwd=ROOT, env=env, text=True).strip()
    report = dict(engine=version, result='PASS', mode='bounded-safety', depth_cycles=args.depth,
        scope='ownership, descriptor freeze, IRQ mask/W1C/set dominance, first-fault retention, AXI response stability, reset',
        assumptions=['reset asserted at initial step'], unbounded_proof=False, liveness_proven=False,
        frontend_normalization='Two function returns changed to equivalent function-name assignments in ignored derivative; properties inserted before endmodule',
        mutations_detected=['W1C removed', 'first-fault overwritten'],
        source_sha256_lf={p.relative_to(ROOT).as_posix():
            hashlib.sha256(p.read_bytes().replace(b'\r\n', b'\n')).hexdigest() for p in (source, props)})
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS: mailbox bounded safety {args.depth} steps; both intentional mutations detected')


if __name__ == '__main__':
    main()
