# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

BAUD_PERIOD_NS = 8680  # ~115200 baud at 1ns timeunit

async def uart_send_byte(dut, byte: int):
    """Send one byte over UART (LSB first)."""
    # Start bit
    dut.ui_in.value = dut.ui_in.value & 0b11111101  # force bit[1] = 0
    await Timer(BAUD_PERIOD_NS, units="ns")

    # Data bits
    for j in range(8):
        bitval = (byte >> j) & 1
        dut.ui_in.value = (dut.ui_in.value & 0b11111101) | (bitval << 1)
        await Timer(BAUD_PERIOD_NS, units="ns")

    # Stop bit
    dut.ui_in.value = (dut.ui_in.value | 0b10)  # bit[1] = 1
    await Timer(BAUD_PERIOD_NS, units="ns")


async def uart_send_word(dut, word: int):
    """Send 64-bit word as 8 bytes MSB first."""
    for shift in range(56, -1, -8):
        byte = (word >> shift) & 0xFF
        await uart_send_byte(dut, byte)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 50 MHz clock (20ns period)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0b10  # idle UART line high on bit[1]
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    dut._log.info("Sending instructions via UART")

    # Instruction sequence (as in your Verilog TB)
    await uart_send_word(dut, 0x00500093)  # addi x1, x0, 5
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00700113)  # addi x2, x0, 7
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x002081B3)  # add x3, x1, x2
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00000013)  # nop
    await uart_send_word(dut, 0x00100073)  # ebreak

    # Allow time for UART + CPU processing
    await Timer(100_000, units="ns")

    # Start CPU
    dut.ui_in.value = dut.ui_in.value | 0b1  # set bit[0] = 1
    dut._log.info("CPU started")

    # Run CPU for some time
    await Timer(10_000, units="ns")

    # Dump internal state
    dut._log.info(f"PC halted at {int(dut.PC.value)}")
    dut._log.info(f"x1 = {int(dut.regfile[1].value)}")
    dut._log.info(f"x2 = {int(dut.regfile[2].value)}")
    dut._log.info(f"x3 = {int(dut.regfile[3].value)} (sum)")

    # Self-check
    assert int(dut.regfile[1].value) == 5, "x1 should be 5"
    assert int(dut.regfile[2].value) == 7, "x2 should be 7"
    assert int(dut.regfile[3].value) == 12, "x3 should be 12"
