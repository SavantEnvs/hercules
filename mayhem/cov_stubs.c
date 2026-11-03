// No-op SanCov callbacks so a standalone reproducer still links when SANITIZER_FLAGS is empty (the
// sanitizer runtime normally supplies them). Weak: libFuzzer / the sanitizer runtime override them.
#include <stdint.h>
#define W __attribute__((weak))
W void __sanitizer_cov_8bit_counters_init(char *s, char *e) { (void)s; (void)e; }
W void __sanitizer_cov_pcs_init(const uintptr_t *s, const uintptr_t *e) { (void)s; (void)e; }
W void __sanitizer_cov_trace_pc_indir(uintptr_t c) { (void)c; }
W void __sanitizer_cov_trace_cmp1(uint8_t a, uint8_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_cmp2(uint16_t a, uint16_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_cmp4(uint32_t a, uint32_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_cmp8(uint64_t a, uint64_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_const_cmp1(uint8_t a, uint8_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_const_cmp2(uint16_t a, uint16_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_const_cmp4(uint32_t a, uint32_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_const_cmp8(uint64_t a, uint64_t b) { (void)a; (void)b; }
W void __sanitizer_cov_trace_switch(uint64_t v, uint64_t *c) { (void)v; (void)c; }
W void __sanitizer_cov_trace_div4(uint32_t v) { (void)v; }
W void __sanitizer_cov_trace_div8(uint64_t v) { (void)v; }
W void __sanitizer_cov_trace_gep(uintptr_t i) { (void)i; }
