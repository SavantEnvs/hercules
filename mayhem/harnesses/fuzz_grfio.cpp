// Fuzzes the GRF archive reader: the input is a .grf file that grfio->init() loads and whose
// every indexed entry is then extracted. Includes grfio.cpp to reach its static file list.
#define HERCULES_CORE
#include "common/grfio.cpp"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern "C" void herc_fuzz_init(void);

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	herc_fuzz_init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (size < 0x2e || size > (1 << 20))
		return -1;
	const char *tmpdir = getenv("TMPDIR");
	if (tmpdir == NULL || *tmpdir == '\0')
		tmpdir = "/tmp";

	char grf_path[512], cfg_path[512];
	snprintf(grf_path, sizeof(grf_path), "%s/hercgrfXXXXXX", tmpdir);
	snprintf(cfg_path, sizeof(cfg_path), "%s/herccfgXXXXXX", tmpdir);
	int fd = mkstemp(grf_path);
	if (fd < 0)
		return 0;
	if (write(fd, data, size) != (ssize_t)size) {
		close(fd);
		unlink(grf_path);
		return 0;
	}
	close(fd);
	int cfd = mkstemp(cfg_path);
	if (cfd < 0) {
		unlink(grf_path);
		return 0;
	}
	FILE *cfg = fdopen(cfd, "w");
	fprintf(cfg, "grf: %s\n", grf_path);
	fclose(cfg);

	grfio->init(cfg_path);
	for (int i = 0; i < filelist_entrys; i++) {
		int out_size = 0;
		char fn[sizeof(filelist[i].fn)];
		safestrncpy(fn, filelist[i].fn, sizeof(fn));
		void *buf = grfio->reads(fn, &out_size);
		if (buf != NULL)
			aFree(buf);
	}
	grfio->final();

	unlink(cfg_path);
	unlink(grf_path);
	return 0;
}
