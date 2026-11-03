// Fuzzes Hercules' libconfig fork through the interface the servers use to read every conf file.
#define HERCULES_CORE
#include "common/cbasetypes.h"
#include "common/conf.h"
#include "common/core.h"
#include "common/showmsg.h"
#include "common/strlib.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" void herc_fuzz_init(void);

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	herc_fuzz_init();
	return 0;
}

static void walk(struct config_setting_t *s, int depth)
{
	if (s == NULL || depth > 64)
		return;
	int len = libconfig->setting_length(s);
	switch (config_setting_type(s)) {
	case CONFIG_TYPE_INT:
		(void)libconfig->setting_get_int(s);
		(void)libconfig->setting_get_int16(s);
		(void)libconfig->setting_get_uint32(s);
		(void)libconfig->setting_get_bool_real(s);
		break;
	case CONFIG_TYPE_INT64:
		(void)libconfig->setting_get_int64(s);
		break;
	case CONFIG_TYPE_FLOAT:
		(void)libconfig->setting_get_float(s);
		break;
	case CONFIG_TYPE_BOOL:
		(void)libconfig->setting_get_bool(s);
		break;
	case CONFIG_TYPE_STRING: {
		const char *str = libconfig->setting_get_string(s);
		if (str != NULL)
			(void)strlen(str);
		break;
	}
	default:
		for (int i = 0; i < len && i < 256; i++)
			walk(libconfig->setting_get_elem(s, i), depth + 1);
		break;
	}
	if (config_setting_name(s) != NULL) {
		int v = 0;
		const char *str = NULL;
		(void)libconfig->setting_lookup_int(s, config_setting_name(s), &v);
		(void)libconfig->setting_lookup_string(s, config_setting_name(s), &str);
	}
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 1 || size > 65536)
		return -1;
	char *buf = (char *)malloc(size + 1);
	memcpy(buf, data, size);
	buf[size] = '\0';

	struct config_t config;
	libconfig->init(&config);
	if (libconfig->read_string(&config, buf) == CONFIG_TRUE) {
		struct config_setting_t *root = config_root_setting(&config);
		walk(root, 0);
		int v = 0;
		const char *str = NULL;
		(void)libconfig->lookup_int(&config, "a.b.c", &v);
		(void)libconfig->lookup_string(&config, "name", &str);
		char out[32];
		(void)libconfig->lookup_mutable_string(&config, "name", out, sizeof(out));
		FILE *f = tmpfile();
		if (f != NULL) {
			libconfig->write(&config, f);
			fclose(f);
		}
		struct config_t copy;
		libconfig->init(&copy);
		libconfig->setting_copy(config_root_setting(&copy), root);
		libconfig->destroy(&copy);
	}
	libconfig->destroy(&config);
	free(buf);
	return 0;
}
