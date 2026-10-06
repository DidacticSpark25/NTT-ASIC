# Reference implementations

Unmodified `ntt.c`, `reduce.c` and headers from the official CRYSTALS reference code,
used only to cross-check the Python golden model (`model/test_model.py`):

| Dir          | Source                                   | Commit     |
|--------------|------------------------------------------|------------|
| `kyber/`     | https://github.com/pq-crystals/kyber/tree/main/ref      | `3edd5af` |
| `dilithium/` | https://github.com/pq-crystals/dilithium/tree/master/ref | `d35ba3f` |

License: public domain (CC0) or Apache 2.0, as stated by the CRYSTALS authors.

`harness.c` (this repo) feeds polynomials through `ntt()` / `invntt()` and prints fully
reduced results with the Montgomery factor removed, so they compare directly with the
standard-domain hardware outputs. Build with `make -C ref`.
