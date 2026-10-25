"""Run with Vitis 2025.2 Python CLI (normally via build_vitis_application.ps1).

Builds a genuine SDT/BSP platform and two linked A53 applications, never a board
connection. Runtime settings are passed in VISION_VITIS_BUILD JSON by the wrapper.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_sections(table: str) -> int:
    allocated = []
    dma = {'.vision_dma_input': 0x10000000, '.vision_dma_output': 0x10001000}
    seen = set()
    for name, kind, addr, size, flags in re.findall(
            r'^\s*\[\s*\d+\]\s+(\S+)\s+(\S+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+\S+\s+(\S+)', table, re.M):
        if 'A' not in flags or int(size, 16) == 0:
            continue
        start, length = int(addr, 16), int(size, 16)
        if name in dma:
            if start != dma[name] or length != 3136 or kind != 'NOBITS':
                raise ValueError('DMA reservation is not the exact NOLOAD frame range')
            seen.add(name)
        elif not 0x100000 <= start < start + length <= 0x10000000:
            raise ValueError('Allocated code/data/heap/stack section outside program DDR')
        allocated.append((start, start + length, name))
    if seen != set(dma) or not any(name == '.text' for _, _, name in allocated):
        raise ValueError('Missing allocated text/DMA sections')
    ordered = sorted(allocated)
    if any(a[1] > b[0] for a, b in zip(ordered, ordered[1:])):
        raise ValueError('Overlapping allocated ELF sections')
    return len(allocated)


def main() -> None:
    import vitis
    config = json.loads(os.environ['VISION_VITIS_BUILD'])
    root = Path(__file__).resolve().parents[1]
    workspace, xsa = Path(config['workspace']).resolve(), Path(config['xsa']).resolve()
    tools = Path(config['toolchain_bin'])
    if not xsa.is_file() or not all((root / 'software/riscv/build' / name).is_file()
                                  for name in ('controller_images.h', 'controller.elf')):
        raise RuntimeError('Build the hardware XSA and RV32 firmware first')
    if workspace == root or workspace in root.parents:
        raise RuntimeError('Use a dedicated generated Vitis workspace')
    client = vitis.create_client()
    try:
        client.set_workspace(str(workspace))
        name, domain = 'vision_platform', 'vision_a53'
        platform_dir = workspace / name
        exported_xsa = platform_dir / 'hw' / xsa.name
        if platform_dir.exists():
            if not exported_xsa.is_file() or sha(exported_xsa) != sha(xsa):
                raise RuntimeError('Existing platform XSA differs; use a new workspace (no automatic deletion)')
            platform = client.get_component(name=name)
        else:
            platform = client.create_platform_component(name=name, hw_design=str(xsa),
                os='standalone', cpu='psu_cortexa53_0', domain_name=domain,
                architecture='64-bit', is_pmufw_req=True)
        if not (platform_dir / 'export' / name / (name + '.xpfm')).is_file():
            platform.build()
        xpfm = client.find_platform_in_repos(name)
        bsp = platform_dir / 'psu_cortexa53_0' / domain / 'bsp'
        if not re.search(r'#define STDOUT_BASEADDRESS 0xff010000', (bsp / 'include/bspconfig.h').read_text()):
            standalone = platform.get_domain(domain)
            standalone.set_config(option='os', param='standalone_stdout', value='psu_uart_1')
            standalone.set_config(option='os', param='standalone_stdin', value='psu_uart_1')
            standalone.regenerate()
            platform.build()
        sdt = bsp / 'hw_artifacts/sdt.dts'
        text = sdt.read_text()
        # Custom IP has no SDT driver YAML exporting its IRQ into xparameters.
        # Derive it from its actual node, requiring one level-high SPI tuple.
        node = re.search(r'\brv32_job_mailbox@a0020000\s*\{([^{}]*)\}', text, re.S)
        if not node:
            raise RuntimeError('Mailbox SDT node missing')
        intr = re.search(r'interrupts\s*=\s*<([^>]+)>', node[1])
        reg = re.search(r'reg\s*=\s*<([^>]+)>', node[1])
        irq = [int(v, 0) for v in intr[1].split()] if intr else []
        address = [int(v, 0) for v in reg[1].split()] if reg else []
        if len(irq) != 3 or irq[0] != 0 or irq[2] != 4 or not 0 <= irq[1] < 988 or address != [0, 0xa0020000, 0, 0x1000]:
            raise RuntimeError('Unsupported mailbox SDT interrupt/address contract')
        generated = workspace / 'vision_generated'
        generated.mkdir(exist_ok=True)
        (generated / 'vision_hw_config.h').write_text(
            '#pragma once\n/* Derived from the generated platform SDT. */\n'
            f'#define VISION_MAILBOX_GIC_ID {irq[1] + 32}u\n')
        results = []
        for model, directory in (('baseline', 'generated/classifier'),
                ('candidate', 'generated/candidates/vector_conv4/classifier')):
            model_dir = root / directory
            manifest = json.loads((model_dir / 'manifest.json').read_text())
            app_name = 'vision_' + model
            app_dir = workspace / app_name
            app = (client.get_component(name=app_name) if app_dir.exists() else
                client.create_app_component(name=app_name, platform=xpfm,
                    domain=domain, template='empty_application'))
            app.import_files(from_loc=str(root / 'software/ultra96'), files=[
                'vision_runtime.c', 'vision_benchmark.c', 'vector_front_reference.c',
                'vector_classifier.c', 'vision_platform_vitis.c', 'vision_demo_vitis.c'])
            includes = [root / 'software/ultra96', root / 'software/riscv/include',
                root / 'software/riscv/build', root / 'generated/test_vectors', model_dir, generated]
            app.set_app_config(key='USER_INCLUDE_DIRECTORIES', values=[p.as_posix() for p in includes])
            app.set_app_config(key='USER_COMPILE_DEFINITIONS', values=[
                'VISION_MODEL_SHA256=' + manifest['checkpoint_sha256']])
            app.set_app_config(key='USER_COMPILE_OPTIMIZATION_LEVEL', values='-O2')
            app.set_app_config(key='USER_COMPILE_WARNINGS_AS_ERRORS', values='-Werror')
            app.set_app_config(key='USER_COMPILE_OTHER_FLAGS', values='-std=c99 -ffp-contract=off')
            ld = app.get_ld_script(path=str(app_dir / 'src/lscript.ld'))
            ld.regenerate()
            ld.set_stack_size('0x10000')
            ld.set_heap_size('0x10000')
            regions = ld.get_memory_regions()
            low = [r for r in regions if r['name'].startswith('psu_ddr_0_') and
                   int(r['base_address'], 0) in (0, 0x100000)]
            if len(low) != 1 or int(low[0]['base_address'], 0) + int(low[0]['size'], 0) < 0x10000000:
                raise RuntimeError('Expected one sufficiently large low DDR memory region')
            ld.update_memory_region(name=low[0]['name'], base_address='0x100000', size='0xff00000')
            if not any(r['name'] == 'vision_dma' for r in regions):
                ld.add_memory_region(name='vision_dma', base_address='0x10000000', size='0x2000')
            linker = Path(ld.file_path).read_text()
            section = '''
.vision_dma_input 0x10000000 (NOLOAD) : {
    KEEP(*(.vision_dma_input))
} > vision_dma
.vision_dma_output 0x10001000 (NOLOAD) : {
    KEEP(*(.vision_dma_output))
} > vision_dma
ASSERT(SIZEOF(.vision_dma_input) == 3136, "unexpected input DMA size")
ASSERT(SIZEOF(.vision_dma_output) == 3136, "unexpected output DMA size")
'''
            linker = linker[:linker.rfind('}')] + section + linker[linker.rfind('}'):]
            reserved = app_dir / 'src/vision_reserved.ld'
            reserved.write_text(linker)
            app.set_app_config(key='USER_LINKER_SCRIPT', values=reserved.as_posix())
            from build_pb2 import BuildResponse
            if app.build() != BuildResponse.SUCCESS:
                raise RuntimeError('Vitis application build returned failure')
            elfs = list((app_dir / 'build').rglob(app_name + '.elf'))
            if len(elfs) != 1:
                raise RuntimeError('Expected exactly one built application ELF')
            elf = elfs[0]
            nm = tools / ('aarch64-none-elf-nm.exe' if os.name == 'nt' else 'aarch64-none-elf-nm')
            symbols = subprocess.check_output([str(nm), '-S', str(elf)], text=True)
            for symbol, expected in (('input_words', 0x10000000), ('output_words', 0x10001000)):
                match = re.search(rf'^([0-9a-f]+)\s+([0-9a-f]+)\s+\w\s+{symbol}$', symbols, re.M)
                if not match or int(match[1], 16) != expected or int(match[2], 16) != 3136:
                    raise RuntimeError('ELF DMA section reservation mismatch')
            readelf = tools / ('aarch64-none-elf-readelf.exe' if os.name == 'nt' else 'aarch64-none-elf-readelf')
            sections = subprocess.check_output([str(readelf), '-W', '-S', str(elf)], text=True)
            section_count = validate_sections(sections)
            results.append(dict(model=model, checkpoint_sha256=manifest['checkpoint_sha256'],
                artifact=elf.name, sha256=sha(elf), allocated_sections_checked=section_count,
                input_address='0x10000000', output_address='0x10001000'))
        receipt = dict(tool='Vitis 2025.2', run_id=config['run_id'], xsa_sha256=sha(xsa), generated_bsp=True,
            linked_elf=True, hardware_execution=False, mailbox_gic_id=irq[1] + 32,
            console='PS UART1 / J1, 115200 8N1',
            program_ddr=dict(origin='0x00100000', length='0x0ff00000'),
            dma_reserved=dict(origin='0x10000000', length='0x2000', frame_bytes=3136), models=results,
            firmware_images_sha256_lf=hashlib.sha256((root / 'software/riscv/build/controller_images.h').read_bytes().replace(b'\r\n', b'\n')).hexdigest(),
            firmware_elf_sha256=sha(root / 'software/riscv/build/controller.elf'),
            source_sha256_lf={p.relative_to(root).as_posix():
                hashlib.sha256(p.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
                for p in sorted((root / 'software/ultra96').glob('*')) if p.suffix in ('.c', '.h')})
        (workspace / 'vision_build_evidence.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('PASS: real generated BSP and two linked A53 ELFs; DMA sections verified; no hardware run')
    finally:
        # Vitis 2025.2 Windows dispose kills its launcher, not the child Java
        # server, leaving the workspace locked. Kill only our owned server tree;
        # never enumerate/terminate other Vitis instances or delete lock files.
        server_process = client._serverObj.cp if os.name == 'nt' else None
        if server_process is not None and server_process.poll() is None:
            subprocess.run(['taskkill', '/PID', str(server_process.pid), '/T', '/F'],
                           capture_output=True, check=False)
        try:
            vitis.dispose()
        except ProcessLookupError:
            pass


if __name__ == '__main__':
    main()
