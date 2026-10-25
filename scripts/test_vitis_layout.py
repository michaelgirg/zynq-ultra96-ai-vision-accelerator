"""Portable negative checks for the linked-ELF memory-layout gate."""
import unittest
from build_vitis_application import validate_sections

TABLE = '''
 [ 1] .text PROGBITS 0000000000100000 010000 012000 00 AX 0 0 256
 [ 2] .stack NOBITS 0000000000200000 020000 010000 00 WA 0 0 64
 [ 3] .vision_dma_input NOBITS 0000000010000000 030000 000c40 00 WA 0 0 64
 [ 4] .vision_dma_output NOBITS 0000000010001000 030000 000c40 00 WA 0 0 64
'''


class LayoutTests(unittest.TestCase):
    def test_reserved_ranges(self):
        self.assertEqual(validate_sections(TABLE), 4)

    def test_unreserved_or_overlapping_dma(self):
        for table in (TABLE.replace('10001000', '10000000'),
                      TABLE.replace('000c40', '000c44'),
                      TABLE.replace('.vision_dma_input NOBITS', '.vision_dma_input PROGBITS')):
            with self.assertRaises(ValueError): validate_sections(table)

    def test_program_outside_reserved_program_ddr(self):
        with self.assertRaises(ValueError): validate_sections(TABLE.replace('00200000', '10000000'))

    def test_missing_or_overlapping_text(self):
        with self.assertRaises(ValueError): validate_sections(TABLE.replace('.text', '.absent'))
        with self.assertRaises(ValueError): validate_sections(TABLE.replace('00200000', '00100000'))


if __name__ == '__main__':
    unittest.main()
