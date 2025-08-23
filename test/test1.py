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


async def uart_send_word(dut, hexstr: str):
    """Send 8 ASCII characters as UART bytes."""
    assert len(hexstr) == 8, "Instruction must be 8 hex chars"
    for ch in hexstr:
        await uart_send_byte(dut, ord(ch))



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
    await uart_send_word(dut, "00500093")  # addi x1, x0, 5
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00700113")  # addi x2, x0, 7
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "002081B3")  # add x3, x1, x2
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00000013")  # nop
    await Timer(1000, units="ns")
    await uart_send_word(dut, "00100073")  # ebreak

    # Allow time for UART + CPU processing
    await Timer(1000, units="ns")

    # Start CPU
    dut.ui_in.value = dut.ui_in.value | 0b1  # set bit[0] = 1
    dut._log.info("CPU started")

    # Run CPU for some time
    await Timer(100000, units="ns")


    # Dump internal state
    #dut._log.info(f"PC halted at {int(dut.user_project.PC.value)}")
    #dut._log.info(f"x1 = {int(dut.user_project.regfile[1].value)}")
    #dut._log.info(f"x2 = {int(dut.user_project.regfile[2].value)}")
    uo_val = int(dut.uo_out.value)   # converts whole bus to Python int
    x3 = (uo_val >> 1) & 0b1111      # shifts + masks → result is also int
    dut._log.info(f"x3 = {x3} (sum)")


    # Self-check
    #assert int(dut.user_project.regfile[1].value) == 5, "x1 should be 5"
    #assert int(dut.user_project.regfile[2].value) == 7, "x2 should be 7"
    assert int(x3) == 12, "x3 should be 12"
