//=============================================================================
// File: axis_checks.svh
// Description: A set of macros for elaboration-time checking of AXI-Stream
//              interface (axis_if) parameters inside modules.
//=============================================================================
`ifndef AXIS_CHECKS_SVH
`define AXIS_CHECKS_SVH

// -----------------------------------------------------------------------
// Generic check "engine": compares an arbitrary interface field
// against an expected value, prints a clear message on mismatch.
// -----------------------------------------------------------------------
`define CHECK_AXIS_FIELD(IF, FIELD, EXPECTED) \
    initial begin \
        if (IF.FIELD !== EXPECTED) begin \
            $fatal(1, "%m: %s.%s = %0d, expected %0d", \
                   `"IF`", `"FIELD`", IF.FIELD, EXPECTED); \
        end \
    end

// -----------------------------------------------------------------------
// Ready-made checks for specific parameters -- convenience wrappers
// around CHECK_AXIS_FIELD. Add new macros here as needed.
// -----------------------------------------------------------------------

// Check data width
`define CHECK_AXIS_WIDTH(IF, EXPECTED) \
    `CHECK_AXIS_FIELD(IF, DATA_WIDTH, EXPECTED)

// Check backpressure (ready) support
`define CHECK_AXIS_HAS_READY(IF, EXPECTED) \
    `CHECK_AXIS_FIELD(IF, HAS_READY, EXPECTED)

// Check last support
`define CHECK_AXIS_HAS_LAST(IF, EXPECTED) \
    `CHECK_AXIS_FIELD(IF, HAS_LAST, EXPECTED)

`endif // AXIS_CHECKS_SVH