// Fuzzes the string helpers every Hercules server uses for db/conf/script parsing and packet text.
#define HERCULES_CORE
#include "common/cbasetypes.h"
#include "common/core.h"
#include "common/showmsg.h"
#include "common/strlib.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern "C" void herc_fuzz_init(void);

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	herc_fuzz_init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 4 || size > 16384)
		return -1;
	const uint8_t sel = data[0];
	const char delim = (char)data[1];
	const int opt = data[2] & 0x1f;
	data += 4;
	size -= 4;
	const int startoff = (int)(data[-1] % (size + 1));

	char *str = (char *)malloc(size + 1);
	memcpy(str, data, size);
	str[size] = '\0';
	const int len = (int)size;

	switch (sel & 7) {
	case 0: {
		int pos[2 + 2 * 8];
		(void)sv->parse(str, len, startoff, delim, pos, ARRAYLENGTH(pos), (enum e_svopt)opt);
		break;
	}
	case 1: {
		char *fields[1 + 8];
		(void)sv->split(str, len, startoff, delim, fields, ARRAYLENGTH(fields), (enum e_svopt)opt);
		break;
	}
	case 2: {
		struct s_svstate st = {};
		st.str = str;
		st.len = len;
		st.delim = delim;
		st.opt = (enum e_svopt)opt;
		int guard = 0;
		while (sv->parse_next(&st) > 0 && guard++ < 100000) { }
		break;
	}
	case 3: {
		char *esc = (char *)malloc(size * 4 + 1);
		size_t n = sv->escape_c(esc, str, size, SV_ESCAPE_C_SUPPORTED);
		char *un = (char *)malloc(n + 1);
		size_t m = sv->unescape_c(un, esc, n);
		(void)m;
		free(un);
		free(esc);
		char *u2 = (char *)malloc(size + 1);
		(void)sv->unescape_c(u2, str, size);
		free(u2);
		(void)sv->skip_escaped_c(str);
		break;
	}
	case 4: {
		char *out = (char *)malloc(size * 4 + 8);
		(void)strlib->jstrescapecpy(out, str);
		(void)strlib->jmemescapecpy(out, str, (int)size);
		free(out);
		char *cp = (char *)malloc(size * 2 + 1);
		memcpy(cp, str, size + 1);
		(void)strlib->jstrescape(cp);
		free(cp);
		break;
	}
	case 5: {
		char *cp = strdup(str);
		(void)remove_control_chars(cp);
		(void)trim(cp);
		(void)normalize_name(cp, " \t");
		(void)e_mail_check(cp);
		(void)config_switch(cp);
		(void)strline(str, (size_t)startoff);
		free(cp);
		break;
	}
	case 6: {
		(void)stristr(str, "ab");
		const char *needle = size > 2 ? str + size / 2 : "x";
		(void)stristr(str, needle);
		char hex[2 * 64 + 1];
		(void)bin2hex(hex, (const unsigned char *)data, size > 64 ? 64 : size);
		char dst[16];
		(void)safestrncpy(dst, str, sizeof(dst));
		(void)safestrnlen(str, size);
		break;
	}
	default: {
		StringBuf *sb = StrBuf->Malloc();
		StrBuf->AppendStr(sb, str);
		StrBuf->Printf(sb, "%d:%s", len, "x");
		StrBuf->Append(sb, sb);
		(void)StrBuf->Value(sb);
		(void)StrBuf->Length(sb);
		StrBuf->Clear(sb);
		StrBuf->Free(sb);
		break;
	}
	}
	free(str);
	return 0;
}
