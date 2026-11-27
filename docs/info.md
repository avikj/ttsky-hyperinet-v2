# tt_um_hyperinet (HyperINet v2)

Programmable dual-lane non-von-Neumann interaction-net processor emitted directly from `lib/silicon/inet-fabric.hypercubical` and verified end-to-end by the metacircular compiler `lib/silicon/inet-compiler.hypercubical`.

- **Architecture:** Zero program counter, zero instruction cache, zero branch predictor, zero global register file. Fires up to 2 disjoint active pairs per clock cycle (`dual_fire = 1`) across Lafont `CON`/`DUP`/`ERA` and fused 8-bit `NUM`/`ADD`/`ADD1` nodes.
- **SkyWater 130nm (`sky130_fd_sc_hd`):** 11,247 standard cells, 211 flip-flops, 0 latches, 65,738.05 um^2.
