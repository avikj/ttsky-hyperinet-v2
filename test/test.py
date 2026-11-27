import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

async def load_field(dut, slot, field, data):
    dut.uio_in.value = ((field & 0x3) << 4) | ((slot & 0x7) << 1) | 1
    dut.ui_in.value = data & 0xFF
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0

async def read_slot(dut, slot):
    dut.uio_in.value = (1 << 7) | ((slot & 0x7) << 1)
    await ClockCycles(dut.clk, 1)
    return int(dut.uo_out.value)

@cocotb.test()
async def test_hyperinet_v2_dual_lane_and_runtime_loader(dut):
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1

    # Phase 1: Built-in dual-lane parallel showcase: (17 + 25 = 42) || DUP(10)
    await ClockCycles(dut.clk, 3)
    assert await read_slot(dut, 2) == 42
    assert await read_slot(dut, 3) == 10
    assert await read_slot(dut, 4) == 10

    # Phase 2: Runtime-loaded program (100 + 23 = 123) via external graph loader
    await load_field(dut, 5, 0, 0x84)  # K_NUM + reset rcnt
    await load_field(dut, 5, 3, 100)
    await load_field(dut, 5, 1, (6 << 2) | 0)
    await load_field(dut, 6, 0, 5)     # K_ADD
    await load_field(dut, 6, 1, (5 << 2) | 0)
    await load_field(dut, 6, 2, (7 << 2) | 0)
    await load_field(dut, 7, 0, 4)     # K_NUM
    await load_field(dut, 7, 3, 23)
    await load_field(dut, 7, 1, (6 << 2) | 1)
    await ClockCycles(dut.clk, 3)
    assert await read_slot(dut, 7) == 123
