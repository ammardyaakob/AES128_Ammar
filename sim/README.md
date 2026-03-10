Run the local simulation flow with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-ghdl-tests.ps1
```

What this does:

- Downloads a pinned local copy of GHDL into `.tools/` if it is not already present.
- Compiles simulation-only UNISIM stubs from `sim/unisim/`.
- Analyzes the RTL and the self-checking VHDL testbenches.
- Elaborates and runs the AES component and top-level tests.

The main regression currently runs:

- `aes_sbox_cf_tb`
- `parallel_to_serial_tb`
- `tb_mixcolumns_multiplier`
- `shifter_serial_tb`
- `aes_key_expansion_tb`
- `aes_top_tb`
