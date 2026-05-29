// tb_ref.cpp -- Verilator C++ testbench + reference model for controller_snes
#include "Vcontroller_snes.h"
#include "verilated.h"
#include <iostream>
#include <cstdint>
#include <array>

// Reference model: compute expected buttons according to HDL rule
// input: 16-bit buttons_buf (as assembled by shifting sampled bits: newest sampled bit becomes MSB)
// rule:
//  if (buttons_buf[15:12] != 0) -> NES: expected = {4'b0, buttons_buf[7:0]}
//  else -> SNES: expected = buttons_buf[11:0]
static uint32_t ref_compute_buttons(uint16_t buttons_buf) {
    uint32_t res;
    if (((buttons_buf >> 12) & 0xF) != 0) {
        // NES mapping: keep low 8 bits, zero-extend to 12 bits
        res = (uint32_t)(buttons_buf & 0xFF);
    } else {
        // SNES mapping: keep bits[11:0]
        res = (uint32_t)(buttons_buf & 0xFFF);
    }
    return res & 0xFFF; // ensure 12-bit
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcontroller_snes* top = new Vcontroller_snes;

    const uint64_t MAX_CYCLES = 4'000'000;
    uint64_t cycles = 0;

    // Initialize DUT IO
    top->clk = 0;
    top->resetn = 0;
    top->joy_data = 1; // pulled-up idle

    // two test patterns: first aims SNES (upper nibble 0), second aims NES (upper nibble non-zero)
    std::array<std::array<int,16>,2> test_patterns = {{
        {1,1,1,1,  0,0,0,0,  1,1,1,1,1,1,1,1}, // pattern 0
        {0,0,0,0,  1,1,1,1,  1,1,1,1,1,1,1,1}  // pattern 1
    }};

    for (int pat = 0; pat < 2; ++pat) {
        // Reset DUT for each pattern (drive a few cycles)
        for (int i = 0; i < 10; ++i) {
            top->clk = 0; top->eval();
            top->clk = 1; top->eval();
        }
        top->resetn = 1;

        // Do an extra eval to let outputs settle, and capture initial observed outputs
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        bool prev_joy_strb = (bool)top->joy_strb;
        bool prev_joy_clk  = (bool)top->joy_clk;

        bool sending = false;
        bool waiting_for_fall = false;
        int bit_idx = 0;
        bool latch_fall_seen = false;

        // local reconstruction of buttons_buf (matches DUT's {~joy_data, buttons_buf[15:1]} behavior)
        uint16_t ref_buttons_buf = 0;

        auto &seq = test_patterns[pat];

        cycles = 0;
        while (cycles < MAX_CYCLES) {
            // NEGEDGE
            top->clk = 0; top->eval();

            // If we're in sending mode and DUT's last observed joy_clk was HIGH, then present the next bit
            // so that when DUT toggles joy_clk low on the upcoming posedge it samples it.
            if (sending && !waiting_for_fall && prev_joy_clk) {
                // drive joy_data according to sequence: 1 => idle(=pulled-up), 0 => pressed
                top->joy_data = seq[bit_idx] ? 1 : 0;
                waiting_for_fall = true;
            }

            // POSEDGE
            top->clk = 1; top->eval();

            bool cur_joy_strb = (bool)top->joy_strb;
            bool cur_joy_clk  = (bool)top->joy_clk;

            // detect latch falling (prev high -> cur low)
            if (!latch_fall_seen && prev_joy_strb && !cur_joy_strb) {
                latch_fall_seen = true;
                sending = true;
                bit_idx = 0;
                waiting_for_fall = false;
                ref_buttons_buf = 0;
                std::cout << "[tb] pattern " << pat << ": detected latch fall -> start sending\n";
            }

            // detect sample event: prev_joy_clk == 1 and cur_joy_clk == 0 implies DUT sampled on this posedge
            if (sending && waiting_for_fall && prev_joy_clk && !cur_joy_clk) {
                // To be robust against tiny timing jitter, use the DUT-observed joy_data at this moment
                // The DUT samples ~joy_data into MSB; so get sampled = ~top->joy_data
                int sampled = top->joy_data ? 0 : 1; // sampled == ~joy_data
                // replicate DUT's shift: buttons_buf <= { sampled, buttons_buf[15:1] }
                ref_buttons_buf = (uint16_t)((sampled << 15) | (ref_buttons_buf >> 1));
                bit_idx++;
                waiting_for_fall = false;
                // default joy_data back to pulled-up
                top->joy_data = 1;
                if (bit_idx >= 16) {
                    sending = false;
                    std::cout << "[tb] pattern " << pat << ": finished sending 16 bits\n";
                }
            }

            // update prevs for next cycle
            prev_joy_strb = cur_joy_strb;
            prev_joy_clk  = cur_joy_clk;

            // once finished sending, wait a little then compare
            if (!sending && latch_fall_seen && bit_idx >= 16) {
                // pump a few cycles for DUT to commit `buttons`
                for (int w = 0; w < 20; ++w) {
                    top->clk = 0; top->eval();
                    top->clk = 1; top->eval();
                }
                uint32_t dut_buttons = (uint32_t)top->buttons & 0xFFF;
                uint32_t expected = ref_compute_buttons(ref_buttons_buf) & 0xFFF;

                std::cout << "[tb] pattern " << pat << ": ref_buttons_buf = 0x"
                          << std::hex << (uint32_t)ref_buttons_buf << std::dec
                          << ", expected(12b) = 0x" << std::hex << expected << std::dec
                          << ", dut buttons = 0x" << std::hex << dut_buttons << std::dec << "\n";

                if (dut_buttons == expected) {
                    std::cout << "PASS (pattern " << pat << ")\n";
                } else {
                    // If still mismatch, print helpful diagnostics (so you can inspect waveforms)
                    std::cout << "FAIL (pattern " << pat << ")\n";
                    std::cout << "  Expected: 0x" << std::hex << expected
                              << "  DUT: 0x" << dut_buttons << std::dec << "\n";
                    delete top;
                    return 1;
                }
                break; // proceed to next pattern
            }

            cycles++;
        }

        if (cycles >= MAX_CYCLES) {
            std::cout << "TIMEOUT pattern " << pat << "\n";
            delete top;
            return 2;
        }
    } // pattern loop

    std::cout << "ALL PATTERNS PASSED\n";
    delete top;
    return 0;
}
